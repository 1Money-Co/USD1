// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DeployHelpers} from "evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";
import {MYieldToOneForcedTransfer} from "evm-m-extensions/src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import {
    TransparentUpgradeableProxy
} from "evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {USD1} from "src/v1/USD1.sol";

/**
 * @title  Deploy
 * @notice Deployment script for USD1 using MYieldToOneForcedTransfer model.
 *         All yield goes to a single designated recipient (treasury).
 *
 * @dev Environment variables:
 *      Required (one of):
 *        - OWNER_PRIVATE_KEY: Deployer's private key (for direct deployment)
 *        - Or use --sender flag for external signing
 *
 *      Role addresses (priority: ADDRESS > PRIVATE_KEY > deployer):
 *        - ADMIN_ADDRESS or derived from deployer
 *        - YIELD_RECIPIENT_ADDRESS or YIELD_RECIPIENT_PRIVATE_KEY
 *        - YIELD_RECIPIENT_MANAGER_ADDRESS or YIELD_RECIPIENT_MANAGER_PRIVATE_KEY
 *        - FREEZE_MANAGER_ADDRESS or FREEZER_PRIVATE_KEY
 *        - PAUSER_ADDRESS or PAUSER_PRIVATE_KEY
 *        - FORCED_TRANSFER_MANAGER_ADDRESS or FORCED_TRANSFER_MANAGER_PRIVATE_KEY
 *
 *      Optional:
 *        - EXTENSION_NAME: Token name (default: "1Money USD1")
 *        - EXTENSION_SYMBOL: Token symbol (default: "USD1")
 *        - CONTRACT_NAME: Salt for CREATE3 (default: "USD1")
 *        - EXISTING_IMPLEMENTATION: Use existing implementation address instead of deploying new one
 *
 * @dev Usage:
 *      # Deploy both implementation and proxy (default)
 *      forge script script/v1/Deploy.s.sol --sig "run()" --rpc-url <rpc_url> --broadcast
 *
 *      # Deploy only implementation
 *      forge script script/v1/Deploy.s.sol --sig "deployImplementation(address,address)" <M_TOKEN> <SWAP_FACILITY> --rpc-url <rpc_url> --broadcast
 *
 *      # Deploy only proxy (with existing implementation)
 *      forge script script/v1/Deploy.s.sol --sig "deployProxy(address)" <IMPLEMENTATION> --rpc-url <rpc_url> --broadcast
 *
 *      # Generate proxy deployment input data (for multisig/safe)
 *      forge script script/v1/Deploy.s.sol --sig "generateProxyDeployInput(address)" <IMPLEMENTATION> --rpc-url <rpc_url>
 */
contract Deploy is Script, DeployHelpers {
    /// @notice Thrown when the script runs on a chain where M0 is not known to be at the addresses below.
    error UnsupportedChain(uint256 chainId);

    /// @dev M0 deploys its protocol contracts through CREATE3, so the M token and SwapFacility share
    ///      one address on Ethereum mainnet, Sepolia, Arbitrum Sepolia, and OP Sepolia.
    address constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    string name;
    string symbol;
    string contractName;

    function setUp() public {
        name = vm.envOr("EXTENSION_NAME", string("1Money USD1"));
        symbol = vm.envOr("EXTENSION_SYMBOL", string("USD1"));
        contractName = vm.envOr("CONTRACT_NAME", string("USD1"));
    }

    /// @notice Deploy both implementation and proxy (full deployment)
    function run() external {
        _requireSupportedChain();

        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        require(deployer != address(0), "Set DEPLOYER_ADDRESS");

        address existingImpl = vm.envOr("EXISTING_IMPLEMENTATION", address(0));

        vm.startBroadcast();

        address implementation;
        if (existingImpl != address(0)) {
            implementation = existingImpl;
            console.log("Using existing Implementation:", implementation);
        } else {
            implementation = _deployImplementation(M_TOKEN, SWAP_FACILITY);
        }

        _deployProxy(implementation, deployer);

        vm.stopBroadcast();
    }

    /// @notice Deploy only the implementation contract
    /// @param mToken_ The M token address
    /// @param swapFacility_ The swap facility address
    /// @return implementation The deployed implementation address
    function deployImplementation(address mToken_, address swapFacility_) external returns (address implementation) {
        console.log("================================================================================");
        console.log("Deploying USD1 Implementation");
        console.log("================================================================================");
        console.log("M Token:", mToken_);
        console.log("Swap Facility:", swapFacility_);

        vm.startBroadcast();
        implementation = _deployImplementation(mToken_, swapFacility_);
        vm.stopBroadcast();

        console.log("================================================================================");
        console.log("Implementation deployed at:", implementation);
        console.log("================================================================================");
    }

    /// @notice Deploy only the proxy contract with an existing implementation
    /// @param implementation_ The implementation contract address
    /// @return proxy The deployed proxy address
    function deployProxy(address implementation_) external returns (address proxy) {
        _requireSupportedChain();

        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        require(deployer != address(0), "Set DEPLOYER_ADDRESS");

        vm.startBroadcast();
        proxy = _deployProxy(implementation_, deployer);
        vm.stopBroadcast();
    }

    /// @notice Generate the proxy deployment input data for CREATE3 factory
    /// @param implementation_ The implementation contract address
    function generateProxyDeployInput(address implementation_) external view {
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        require(deployer != address(0), "Set DEPLOYER_ADDRESS");

        (bytes32 salt, bytes memory initCode, bytes memory initializerData) =
            _getProxyDeploymentData(implementation_, deployer);

        address expectedProxy = _getCreate3Address(deployer, salt);

        console.log("================================================================================");
        console.log("Proxy Deployment Input Data (for CREATE3)");
        console.log("================================================================================");
        console.log("Implementation:", implementation_);
        console.log("Deployer:", deployer);
        console.log("Contract Name:", contractName);
        console.log("Expected Proxy Address:", expectedProxy);
        console.log("--------------------------------------------------------------------------------");
        console.log("CREATE_X_FACTORY:", CREATE_X_FACTORY);
        console.log("--------------------------------------------------------------------------------");
        console.log("Salt:");
        console.logBytes32(salt);
        console.log("--------------------------------------------------------------------------------");
        console.log("Initializer Data:");
        console.logBytes(initializerData);
        console.log("--------------------------------------------------------------------------------");
        console.log("Proxy Init Code (TransparentUpgradeableProxy creationCode + encoded args):");
        console.logBytes(initCode);
        console.log("--------------------------------------------------------------------------------");
        console.log("deployCreate3 calldata (call this on CREATE_X_FACTORY):");
        bytes memory deployCreate3Calldata = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode);
        console.logBytes(deployCreate3Calldata);
        console.log("================================================================================");
    }

    /// @notice Predict the proxy address before deployment
    function predictAddress() external view {
        address deployer = _getDeployer();

        bytes32 salt = _computeSalt(deployer, contractName);
        address expectedProxy = _getCreate3Address(deployer, salt);

        console.log("Deployer:", deployer);
        console.log("Contract Name:", contractName);
        console.log("Salt:", vm.toString(salt));
        console.log("Predicted Proxy Address:", expectedProxy);
    }

    // ==================== Internal Functions ====================

    /// @dev Revert unless the current chain is one where M_TOKEN and SWAP_FACILITY are known to live
    function _requireSupportedChain() internal view {
        uint256 chainId = block.chainid;
        if (chainId == 1 || chainId == 11155111 || chainId == 421614 || chainId == 11155420) return;
        revert UnsupportedChain(chainId);
    }

    /// @dev Deploy the implementation contract
    function _deployImplementation(address mToken_, address swapFacility_) internal returns (address) {
        address implementation = address(new USD1(mToken_, swapFacility_));
        console.log("Implementation deployed at:", implementation);
        return implementation;
    }

    /// @dev Deploy the proxy contract via CREATE3
    function _deployProxy(address implementation_, address deployer_) internal returns (address proxy) {
        // Get role addresses
        address admin = vm.envOr("ADMIN_ADDRESS", deployer_);
        address yieldRecipient = _getAddress("YIELD_RECIPIENT_ADDRESS", "YIELD_RECIPIENT_PRIVATE_KEY", deployer_);
        address yieldRecipientManager =
            _getAddress("YIELD_RECIPIENT_MANAGER_ADDRESS", "YIELD_RECIPIENT_MANAGER_PRIVATE_KEY", yieldRecipient);
        address freezeManager = _getAddress("FREEZE_MANAGER_ADDRESS", "FREEZER_PRIVATE_KEY", deployer_);
        address pauser = _getAddress("PAUSER_ADDRESS", "PAUSER_PRIVATE_KEY", deployer_);
        address forcedTransferManager =
            _getAddress("FORCED_TRANSFER_MANAGER_ADDRESS", "FORCED_TRANSFER_MANAGER_PRIVATE_KEY", deployer_);

        console.log("================================================================================");
        console.log("Deploying USD1 Proxy");
        console.log("================================================================================");
        console.log("Model: MYieldToOneForcedTransfer (All yield to single recipient)");
        console.log("--------------------------------------------------------------------------------");
        console.log("Implementation:", implementation_);
        console.log("Deployer:", deployer_);
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Contract Name (for salt):", contractName);
        console.log("Yield Recipient:", yieldRecipient);
        console.log("Admin:", admin);
        console.log("Freeze Manager:", freezeManager);
        console.log("Yield Recipient Manager:", yieldRecipientManager);
        console.log("Pauser:", pauser);
        console.log("Forced Transfer Manager:", forcedTransferManager);

        // Compute deterministic salt and predict address
        bytes32 salt = _computeSalt(deployer_, contractName);
        address expectedProxy = _getCreate3Address(deployer_, salt);

        console.log("--------------------------------------------------------------------------------");
        console.log("Salt:", vm.toString(salt));
        console.log("Expected Proxy Address:", expectedProxy);
        console.log("--------------------------------------------------------------------------------");

        // Deploy proxy via CREATE3
        proxy = _deployCreate3TransparentProxy(
            implementation_,
            admin,
            abi.encodeWithSelector(
                MYieldToOneForcedTransfer.initialize.selector,
                name,
                symbol,
                yieldRecipient,
                admin,
                freezeManager,
                yieldRecipientManager,
                pauser,
                forcedTransferManager
            ),
            salt
        );

        console.log("Proxy deployed at:", proxy);

        // Verify address match
        require(proxy == expectedProxy, "Address mismatch!");
        console.log("Address verification: PASSED");

        // Get ProxyAdmin address
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("ProxyAdmin:", proxyAdmin);

        console.log("================================================================================");
        console.log("Deployment successful!");
        console.log("================================================================================");
        console.log("Extension Address (use this):", proxy);
        console.log("Implementation:", implementation_);
        console.log("ProxyAdmin:", proxyAdmin);

        return proxy;
    }

    /// @dev Get proxy deployment data without executing
    function _getProxyDeploymentData(address implementation_, address deployer_)
        internal
        view
        returns (bytes32 salt, bytes memory initCode, bytes memory initializerData)
    {
        // Get role addresses
        address admin = vm.envOr("ADMIN_ADDRESS", deployer_);
        address yieldRecipient = _getAddress("YIELD_RECIPIENT_ADDRESS", "YIELD_RECIPIENT_PRIVATE_KEY", deployer_);
        address yieldRecipientManager =
            _getAddress("YIELD_RECIPIENT_MANAGER_ADDRESS", "YIELD_RECIPIENT_MANAGER_PRIVATE_KEY", yieldRecipient);
        address freezeManager = _getAddress("FREEZE_MANAGER_ADDRESS", "FREEZER_PRIVATE_KEY", deployer_);
        address pauser = _getAddress("PAUSER_ADDRESS", "PAUSER_PRIVATE_KEY", deployer_);
        address forcedTransferManager =
            _getAddress("FORCED_TRANSFER_MANAGER_ADDRESS", "FORCED_TRANSFER_MANAGER_PRIVATE_KEY", deployer_);

        // Compute salt
        salt = _computeSalt(deployer_, contractName);

        // Build initializer data
        initializerData = abi.encodeWithSelector(
            MYieldToOneForcedTransfer.initialize.selector,
            name,
            symbol,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        // Build proxy init code (creationCode + constructor args)
        initCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation_, admin, initializerData)
        );
    }

    /// @dev Get deployer address from env
    function _getDeployer() internal view returns (address) {
        uint256 ownerPk = vm.envOr("OWNER_PRIVATE_KEY", uint256(0));
        if (ownerPk != 0) {
            return vm.addr(ownerPk);
        }
        return vm.envAddress("DEPLOYER_ADDRESS");
    }

    /// @notice Get address from env: try direct address first, then private key, then fallback
    function _getAddress(string memory addrEnvKey, string memory pkEnvKey, address fallback_)
        internal
        view
        returns (address)
    {
        // Try direct address first
        address addr = vm.envOr(addrEnvKey, address(0));
        if (addr != address(0)) {
            return addr;
        }

        // Try deriving from private key
        uint256 pk = vm.envOr(pkEnvKey, uint256(0));
        if (pk != 0) {
            return vm.addr(pk);
        }

        // Fallback
        return fallback_;
    }
}
