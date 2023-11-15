import { createRequire } from "module";
const require = createRequire(import.meta.url);

const Web3 = require("web3");

const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;

const web3 = createAlchemyWeb3("wss://eth-sepolia.g.alchemy.com/v2/D-7jdz-GDlNmGqStzuAK9w2kH5I0mpDq");

const factoryAddress = "0xbF551B0A75774E52B3B830c49690d11eCaF072eB";
const myFactory = new web3.eth.Contract(factoryAbi, factoryAddress);

const myAddress = "0x2B29A54bc2b62a2BADf1C2090A07Db84f19976DB";

async function createNewRaffle() {

  const name = "ORBIT";
  const symbol = "ORB";
  const uri = "https://orbitnft.io/tokenID_"
  const raw_entryFee = amount * 1000000000000000000000;
  const msgValue = web3.utils.toBN(raw_entryFee).toString();
  const grandMargin = 50;
  const minorMargin = 10;
  const bonusWins = 7;
  const operatorMargin = 12;
  const timer = 100;
  const owner = "0xBda12ccD24974b67710876171Ab1F3C5a2EF3ED3";
  const token = "0xBA62BCfcAaFc6622853cca2BE6Ac7d845BC0f2Dc";

  var gasEstimate = await myFactory.methods.createNewRaffle(name, symbol, uri, entryFee, grandMargin, minorMargin, bonusWins, operatorMargin, timer, owner, token).estimateGas({from: myAddress});
  console.log("Gas estimate:", gasEstimate);

  let nonce = await web3.eth.getTransactionCount(myAddress, 'latest');
  console.log(nonce);
  let maxPriorityFeePerGasEstimate = await web3.eth.getMaxPriorityFeePerGas();
  console.log(maxPriorityFeePerGasEstimate);

  const tx = {
      from: myAddress,
      to: factoryAddress,
      value: 0,
      gas: gasEstimate,
      maxPriorityFeePerGas: maxPriorityFeePerGasEstimate,
      nonce: nonce,
      // this encodes the ABI of the method and the arguements
      data: myFactory.methods.createNewRaffle(name, symbol, uri, entryFee, grandMargin, minorMargin, bonusWins, operatorMargin, timer, owner, token).encodeABI()
    };

  const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
  console.log(signedTx);

  web3.eth.sendSignedTransaction(signedTx.rawTransaction, function(error, hash) {
    if (!error) {
      console.log("🎉 The hash of your transaction is: ", hash, "\n Check Goerli Etherscan to view the status of your transaction!");
    } else {
      console.log("❗Something went wrong while submitting your transaction:", error)
    }
  });
};

async function gasEstimate() {

  const raffleAddress = "0x7BD81505F8F46Bf0B5D8FfC56dd0EfD461144d4B";

  var gasEstimate = await myFactory.methods.getWinners(raffleAddress).estimateGas({from: myAddress});
  console.log("Gas estimate:", gasEstimate);
}

createNewRaffle();
