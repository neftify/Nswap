const Nswap = artifacts.require('Nswap');

contract('Nswap', () => {
    let nSwap = null;

    before(async() => {
        nSwap = await Nswap.deployed();
    });

    it('Should deploy smart contract properly', async () => {
        assert(nSwap.address !== '');
    });
});