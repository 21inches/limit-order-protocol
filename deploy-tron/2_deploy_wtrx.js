const WTRX = artifacts.require('WETH9_21Inches');

module.exports = function (deployer) {
    deployer.deploy(WTRX);
};
