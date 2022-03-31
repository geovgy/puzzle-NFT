const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFT", function () {
  let earnedNFTContract;
  let royaltyContract;

  const name = 'Earned NFT';
  const symbol = 'EARN';
  const URIs = [
    {
      gen: 0,
      baseURI: 'BASE-0',
      tokenURIs: ['TOKEN-0A', 'TOKEN-0B', 'TOKEN-0C', 'TOKEN-0D']
    },
    {
      gen: 1,
      baseURI: 'BASE-1',
      tokenURIs: ['TOKEN-1A', 'TOKEN-1B', 'TOKEN-1C', 'TOKEN-1D']
    }
  ];

  before("Deploy NFT contract", async () => {
    const Factory = await ethers.getContractFactory("RoyaltySplitterFactory");
    const factory = await Factory.deploy();
    await factory.deployed();

    const EarnedNFT = await ethers.getContractFactory("EarnedNFT");
    earnedNFTContract = await EarnedNFT.deploy(
      name, symbol, URIs[0].baseURI, URIs[0].tokenURIs, factory.address
    );
    await earnedNFTContract.deployed();
  });

  it("NFT contract successfully deployed", () => {
    expect(earnedNFTContract.address);
  });

  it("Max supply equals length of token URIs", async () => {
    const maxSupply = await earnedNFTContract.maxSupply();
    expect(maxSupply).to.equal(URIs[0].tokenURIs.length);
  });

  it("Minting only done by owner", async () => {
    const [owner, user] = await ethers.getSigners();
    let reverted;
    try {
      await earnedNFTContract.connect(user).mint(user.address);
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();

    await earnedNFTContract.connect(owner).mint(user.address);
    const balance = await earnedNFTContract.balanceOf(user.address);
    const balanceNumber = ethers.BigNumber.from(balance).toNumber();
    expect(balanceNumber).to.equal(1);
  });
  
  it("Royalty info of token", async () => {
    const tokenId = 1;
    const salePrice = ethers.utils.parseEther('100');
    
    const royaltyInfo = await earnedNFTContract.royaltyInfo(tokenId, salePrice);
    const royaltyReceiver = await earnedNFTContract.royaltyReceiver(tokenId);
    const { receiver, royaltyAmount } = royaltyInfo;
    const amountNormalized = parseFloat(ethers.utils.formatEther(royaltyAmount));
    
    expect(receiver).to.equal(royaltyReceiver);
    expect(amountNormalized).to.equal(5);
  });
  
  it("Royalty Splitter exists", async () => {
    const tokenId = 1;
    const royaltyReceiver = await earnedNFTContract.royaltyReceiver(tokenId);
    const [owner, user] = await ethers.getSigners();
    royaltyContract = new ethers.Contract(
      royaltyReceiver,
      require('../artifacts/contracts/RoyaltySplitter.sol/RoyaltySplitter.json').abi,
      owner
    );
      
    expect(royaltyContract.address);
  });
  
  it("Shares are distributed correctly", async () => {
    const [owner, user] = await ethers.getSigners();
    const totalShares = await royaltyContract.totalShares();
    const userShares = await royaltyContract.shares(user.address);
    const ownerShares = await royaltyContract.shares(owner.address);
    
    const totalSharesNormalized = ethers.BigNumber.from(totalShares).toNumber();
    const userSharesNormalized = ethers.BigNumber.from(userShares).toNumber();
    const ownerSharesNormalized = ethers.BigNumber.from(ownerShares).toNumber();
    
    expect(totalSharesNormalized).to.equal(5).and.equal(userSharesNormalized + ownerSharesNormalized);
    expect(ownerSharesNormalized).to.equal(4);
    expect(userSharesNormalized).to.equal(1);
  });

  it("Cannot burn tokens until all are minted", async () => {
    let reverted;
    try {
      await earnedNFTContract.burn();
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();
  });

  it("Cannot mint more than max supply", async () => {
    const [, user, user2] = await ethers.getSigners();
    for(let i=1; URIs[0].tokenURIs.length > i; i++) {
      await earnedNFTContract.mint(user2.address);
    }

    let reverted;
    try {
      await earnedNFTContract.mint(user.address);
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();
  });

  it("Unable to change token URIs while active", async () => {
    let reverted;
    try {
      await earnedNFTContract.setNewTokenURIs(
        'NEW BASE', ['URI1', 'URI2', 'URI3']
      );
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();
  });

  it("Cannot burn until all tokens are owned by one address", async () => {
    const [owner, user, user2] = await ethers.getSigners();
    let reverted;
    try {
      await earnedNFTContract.connect(user2).burn();
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();

    const tokenId = 1;
    await earnedNFTContract.connect(user).transferFrom(user.address, user2.address, tokenId);

    const balance = await earnedNFTContract.balanceOf(user2.address);
    const balanceNormalized = ethers.BigNumber.from(balance).toNumber();
    const maxSupply = await earnedNFTContract.maxSupply();

    expect(balanceNormalized).to.equal(maxSupply);

    await earnedNFTContract.connect(user2).burn();
  });

  it("Token with Base URI minted to user during burning", async () => {
    const [,,user2] = await ethers.getSigners();
    const tokenId = URIs[0].gen;
    const tokenOwner = await earnedNFTContract.ownerOf(tokenId);
    expect(tokenOwner).to.equal(user2.address);
  });
  
  it("Cannot mint new tokens until unpaused", async () => {
    const [owner] = await ethers.getSigners();
    let reverted;
    try {
      await earnedNFTContract.mint(owner.address);
    } catch (error) {
      reverted = true;
      expect(error);
    }

    if (!reverted) return expect.fail();
  });

  xit("Add new token URIs and reset game");
});
  