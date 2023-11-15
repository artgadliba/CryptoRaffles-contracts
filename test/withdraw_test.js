import { createRequire } from "module";
const require = createRequire(import.meta.url);

const Web3 = require("web3");

const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
const ercAbi = require("../abi/ERC20token_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;
const apiKey = process.env.API_WSS;

const web3 = createAlchemyWeb3("wss://eth-goerli.g.alchemy.com/v2/fX1ZXyGCJ05IY2TEGhSCqoR2qSQ2nWFz");

const factoryAddress = "0xbF551B0A75774E52B3B830c49690d11eCaF072eB";
const rafflesAddress = "0xfaa9407A306EA9737dD6BFad509Cb215d8a7ECe0";
const ercAddress = "0xBA62BCfcAaFc6622853cca2BE6Ac7d845BC0f2Dc";
const myFactory = new web3.eth.Contract(factoryAbi, factoryAddress);
const myRaffle = new web3.eth.Contract(rafflesAbi, rafflesAddress);
const myERC = new web3.eth.Contract(ercAbi, ercAddress);

const address2key = {
  '0x2B29A54bc2b62a2BADf1C2090A07Db84f19976DB': process.env.PRIVATE_KEY,
  '0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8': process.env.PRIVATE_KEY_1,
  '0x01299e30c37778B210b6b196fDEB3cB82F37227E': process.env.PRIVATE_KEY_2,
  '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96': process.env.PRIVATE_KEY_3,
  '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D': process.env.PRIVATE_KEY_4,
  '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98': process.env.PRIVATE_KEY_5,
  '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83': process.env.PRIVATE_KEY_6,
  '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b': process.env.PRIVATE_KEY_7,
  '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac': process.env.PRIVATE_KEY_8,
  '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB': process.env.PRIVATE_KEY_9,
  '0x05B368b1d8672d4c9001B635c5b03235508F83F8': process.env.PRIVATE_KEY_10,
  '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792': process.env.PRIVATE_KEY_11,
  '0xe97dEE2eeec1189365FCb05d619234e39838522c': process.env.PRIVATE_KEY_12,
  '0xC46aab22487F0A67A17997bE1E9979588692fBf1': process.env.PRIVATE_KEY_13,
  '0xBda12ccD24974b67710876171Ab1F3C5a2EF3ED3': process.env.PRIVATE_KEY_14
};

async function withdraw() {

  const prizeIDs = [
      '25', '11', '33',
      '23', '26', '7',
      '1', '14'
    ]

  for (let i = 0; i <= prizeIDs.length; i ++) {

    if (i == prizeIDs.length) {
      console.log('WITHDRAW IS FINISHED')
      checkContractBalance();
    } else {
      var tokenID = prizeIDs[i];
      console.log(tokenID);
      var ownerAddress = await myRaffle.methods.ownerOf(tokenID).call();

      if (web3.utils.isAddress(ownerAddress) == true) {
        console.log(ownerAddress + "\nTRUE ADDRESS");

        var success_stage1 = false;
        try {
          var gasEstimate = await myRaffle.methods.withdrawPrize(tokenID).estimateGas({from: ownerAddress});
          console.log("Gas estimate:", gasEstimate);
          success_stage1 = true;
        } catch (error) {
          console.log(error);
        } if (success_stage1) {

          let nonce = await web3.eth.getTransactionCount(ownerAddress, 'latest');
          console.log(nonce);
          let maxPriorityFeePerGasEstimate = await web3.eth.getMaxPriorityFeePerGas();
          console.log(maxPriorityFeePerGasEstimate);

          const tx = {
              from: ownerAddress,
              to: rafflesAddress,
              value: 0,
              gas: gasEstimate,
              maxPriorityFeePerGas: maxPriorityFeePerGasEstimate,
              nonce: nonce,
              // this encodes the ABI of the method and the arguements
              data: myRaffle.methods.withdrawPrize(tokenID).encodeABI()
            };

          const signedTx = await web3.eth.accounts.signTransaction(tx, address2key[ownerAddress]);
          console.log(signedTx);

          var success_stage2 = false;
          try{
            await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
            success_stage2 = true;
          } catch (error) {
            console.log("❗Something went wrong while submitting your transaction:", error);
          } if (success_stage2) {
            console.log("🎉 The hash of your transaction is: ", signedTx.transactionHash, "\n Check Goerli Etherscan to view the status of your transaction!");
          }
        };
      }
    }
  };
};

async function checkContractBalance() {

  var balance = await myERC.methods.balanceOf(factoryAddress).call();
  console.log(balance);
}

checkContractBalance();
