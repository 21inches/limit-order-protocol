const hre = require('hardhat');
const { getChainId, network } = hre;

const wethByNetwork = {
    hardhat: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    mainnet: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    sepolia: '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14',
    baseSepolia: '0x1Ac57B55b351151ec6c8C656a9B46E528B014945',
    xtzGhostnet: '0x1Ac57B55b351151ec6c8C656a9B46E528B014945',
};

module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log('running deploy script');
    console.log('network id ', await getChainId());

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const limitOrderProtocol = await deploy('LimitOrderProtocol', {
        from: deployer,
        gasLimit: 30_000_000,
    });

    console.log('LimitOrderProtocol deployed to:', limitOrderProtocol.address);

    if (await getChainId() !== '31337') {
        await hre.run('verify:verify', {
            address: limitOrderProtocol.address,
        });
    }
};
