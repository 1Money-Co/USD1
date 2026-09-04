// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    TransparentUpgradeableProxy
} from "evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {USD1} from "src/v1/USD1.sol";
import {Deploy} from "script/v1/Deploy.s.sol";

/// @dev Minimal CREATE3 stand-in for CreateX, copied from 1USD's test/v3/DeployOneUSDV3.t.sol.
contract LocalCreate3Proxy {
    error DeploymentFailed();

    function deploy(bytes memory initCode) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }
}

/// @dev Applies CreateX's guarded-salt rule for permissioned salts (deployer in the leading
///      20 bytes, cross-chain protection byte 0x00): guardedSalt = keccak256(abi.encode(sender, salt)).
contract LocalCreateX {
    error DeploymentFailed();

    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address deployed) {
        bytes32 guardedSalt = keccak256(abi.encode(bytes32(uint256(uint160(msg.sender))), salt));
        LocalCreate3Proxy proxy = new LocalCreate3Proxy{salt: guardedSalt}();
        deployed = proxy.deploy(initCode);
    }

    function computeCreate3Address(bytes32 guardedSalt) external view returns (address) {
        bytes32 proxyHash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), guardedSalt, keccak256(type(LocalCreate3Proxy).creationCode))
        );
        address proxy = address(uint160(uint256(proxyHash)));
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }
}

interface IOwnable {
    function owner() external view returns (address);
}

contract DeployHarness is Deploy {
    function exposeDeployProxy(address implementation_, address deployer_) external returns (address) {
        return _deployProxy(implementation_, deployer_);
    }

    function exposeProxyDeploymentData(address implementation_, address deployer_)
        external
        view
        returns (bytes32 salt, bytes memory initCode, bytes memory initializerData)
    {
        return _getProxyDeploymentData(implementation_, deployer_);
    }

    function exposeComputeSalt(address deployer_, string memory contractName_) external pure returns (bytes32) {
        return _computeSalt(deployer_, contractName_);
    }

    function exposePredict(address deployer_, bytes32 salt_) external view returns (address) {
        return _getCreate3Address(deployer_, salt_);
    }

    function exposeRequireSupportedChain() external view {
        _requireSupportedChain();
    }
}

contract DeployUSD1Test is Test {
    address internal constant CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    address internal constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;
    bytes4 internal constant INITIALIZE_SELECTOR =
        bytes4(keccak256("initialize(string,string,address,address,address,address,address,address)"));

    DeployHarness internal harness;
    USD1 internal implementation;

    address internal admin;
    address internal yieldRecipient;
    address internal yieldRecipientManager;
    address internal freezeManager;
    address internal pauser;
    address internal forcedTransferManager;

    function setUp() public {
        // The script talks to CreateX at a fixed address; put a local CREATE3 factory there.
        vm.etch(CREATE_X, address(new LocalCreateX()).code);

        harness = new DeployHarness();
        implementation = new USD1(M_TOKEN, SWAP_FACILITY);

        admin = makeAddr("admin");
        yieldRecipient = makeAddr("yieldRecipient");
        yieldRecipientManager = makeAddr("yieldRecipientManager");
        freezeManager = makeAddr("freezeManager");
        pauser = makeAddr("pauser");
        forcedTransferManager = makeAddr("forcedTransferManager");

        // Foundry loads the developer's .env into tests, so pin every variable the script reads.
        // Under forge test the factory sees the harness as msg.sender, so the harness is the deployer.
        vm.setEnv("DEPLOYER_ADDRESS", vm.toString(address(harness)));
        vm.setEnv("ADMIN_ADDRESS", vm.toString(admin));
        vm.setEnv("YIELD_RECIPIENT_ADDRESS", vm.toString(yieldRecipient));
        vm.setEnv("YIELD_RECIPIENT_MANAGER_ADDRESS", vm.toString(yieldRecipientManager));
        vm.setEnv("FREEZE_MANAGER_ADDRESS", vm.toString(freezeManager));
        vm.setEnv("PAUSER_ADDRESS", vm.toString(pauser));
        vm.setEnv("FORCED_TRANSFER_MANAGER_ADDRESS", vm.toString(forcedTransferManager));
        vm.setEnv("EXTENSION_NAME", "1Money USD1");
        vm.setEnv("EXTENSION_SYMBOL", "USD1");
        vm.setEnv("CONTRACT_NAME", "USD1");
        vm.setEnv("EXISTING_IMPLEMENTATION", vm.toString(address(0)));
        vm.setEnv("OWNER_PRIVATE_KEY", "0");

        // forge runs a script's setUp() only under `forge script`.
        harness.setUp();

        vm.chainId(11155111);
    }

    function _expectedInitializerData() internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            INITIALIZE_SELECTOR,
            "1Money USD1",
            "USD1",
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );
    }

    function test_ProxyLandsAtPredictedAddressAndIsInitialized() public {
        bytes32 salt = harness.exposeComputeSalt(address(harness), "USD1");
        address predicted = harness.exposePredict(address(harness), salt);

        address proxy = harness.exposeDeployProxy(address(implementation), address(harness));
        assertEq(proxy, predicted);

        USD1 token = USD1(proxy);
        assertEq(token.name(), "1Money USD1");
        assertEq(token.symbol(), "USD1");
        assertEq(token.decimals(), 6);
        assertEq(token.yieldRecipient(), yieldRecipient);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.FREEZE_MANAGER_ROLE(), freezeManager));
        assertTrue(token.hasRole(token.YIELD_RECIPIENT_MANAGER_ROLE(), yieldRecipientManager));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), pauser));
        assertTrue(token.hasRole(token.FORCED_TRANSFER_MANAGER_ROLE(), forcedTransferManager));

        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        assertGt(proxyAdmin.code.length, 0);
        assertEq(IOwnable(proxyAdmin).owner(), admin);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(
            "again", "AGAIN", yieldRecipient, admin, freezeManager, yieldRecipientManager, pauser, forcedTransferManager
        );
    }

    function test_SaltLayoutAndDistinctFromOneUSD() public view {
        bytes32 salt = harness.exposeComputeSalt(address(harness), "USD1");
        bytes32 expected =
            bytes32(abi.encodePacked(bytes20(address(harness)), bytes1(0), bytes11(keccak256(bytes("USD1")))));
        assertEq(salt, expected);

        bytes32 oneUsdSalt = harness.exposeComputeSalt(address(harness), "OneUSD");
        assertNotEq(salt, oneUsdSalt);
        assertNotEq(harness.exposePredict(address(harness), salt), harness.exposePredict(address(harness), oneUsdSalt));
    }

    function test_ProxyDeploymentDataMatchesEncoding() public view {
        (bytes32 salt, bytes memory initCode, bytes memory initializerData) =
            harness.exposeProxyDeploymentData(address(implementation), address(harness));

        assertEq(salt, harness.exposeComputeSalt(address(harness), "USD1"));
        // _expectedInitializerData is built from the hand-computed selector, so this pins the selector too.
        assertEq(initializerData, _expectedInitializerData());
        assertEq(
            initCode,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), admin, initializerData)
            )
        );
    }

    function test_RequireSupportedChain() public {
        uint256[4] memory supported = [uint256(1), 11155111, 421614, 11155420];
        for (uint256 i = 0; i < supported.length; i++) {
            vm.chainId(supported[i]);
            harness.exposeRequireSupportedChain();
        }

        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 31337));
        harness.exposeRequireSupportedChain();
    }
}
