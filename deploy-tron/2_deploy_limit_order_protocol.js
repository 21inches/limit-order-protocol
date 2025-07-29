const LimitOrderProtocol = artifacts.require('LimitOrderProtocol');

const wethByNetwork = {
    tron: 'TUrzzZSyCtu2aXdkxnwUqNpqBgoodrbN8Y', // TODO: Mainnet WETH address on Tron
    nile: 'TUrzzZSyCtu2aXdkxnwUqNpqBgoodrbN8Y', // TODO: Mainnet WETH address on Tron
};

module.exports = async function (deployer, network, accounts) {
    console.log('Running deployment for LimitOrderProtocol...');
    console.log(`Network: ${network}`);
    console.log(`Deployer account: ${accounts}`);

    // =================================================================
    // 2. Select Configuration and Deploy
    // =================================================================

    const networkConfig = wethByNetwork[network];

    // Safety check: fail if the network is not configured
    if (!networkConfig) {
        throw new Error(`Configuration for network "${network}" not found. Please add it to the script.`);
    }

    // Deploy the contract with the network-specific arguments
    await deployer.deploy(LimitOrderProtocol, networkConfig);

    const limitOrderProtocol = await LimitOrderProtocol.deployed();
    console.log('LimitOrderProtocol deployed to:', limitOrderProtocol.address);
};
