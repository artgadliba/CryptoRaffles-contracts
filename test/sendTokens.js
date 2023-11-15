import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { Alchemy, Network, Wallet, Utils } = require("alchemy-sdk");
const fs = require("fs-extra");
import { ethers } from "ethers";

const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
const ercAbi = require("../abi/ERC20token_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;
const apiURL = process.env.API_URL;
const apiKey = process.env.API_KEY;

const provider = new ethers.providers.JsonRpcProvider(apiURL)
const signer = new ethers.Wallet(privateKey, provider);

const settings = {
  apiKey: apiKey,
  network: Network.ETH_SEPOLIA,
};
const alchemy = new Alchemy(settings);

const factoryAddress = "0x388e968242A24125408eD239B363CA62d7Ae287C";
const rafflesAddress = "0x07EA3DA7F7Ef52f16127F8Ba4E1AEC133692E1F5";
const ercAddress = "0xFcc09DEB3Ce135d58ED0c4e7c6D8b59790A9a03b";
const myFactory = new ethers.Contract(factoryAddress, factoryAbi, signer);
const myRaffle = new ethers.Contract(rafflesAddress, rafflesAbi, signer);
const myERC = new ethers.Contract(ercAddress, ercAbi, signer);

const addresses = ['0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8', '0x01299e30c37778B210b6b196fDEB3cB82F37227E', '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96', '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D', '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98', '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83', '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b', '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac', '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB', '0x05B368b1d8672d4c9001B635c5b03235508F83F8', '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792', '0xe97dEE2eeec1189365FCb05d619234e39838522c', '0xC46aab22487F0A67A17997bE1E9979588692fBf1'];

const privateKeys = [process.env.PRIVATE_KEY_1, process.env.PRIVATE_KEY_2, process.env.PRIVATE_KEY_3, process.env.PRIVATE_KEY_4, process.env.PRIVATE_KEY_5, process.env.PRIVATE_KEY_6, process.env.PRIVATE_KEY_7, process.env.PRIVATE_KEY_8, process.env.PRIVATE_KEY_9, process.env.PRIVATE_KEY_10, process.env.PRIVATE_KEY_11, process.env.PRIVATE_KEY_12, process.env.PRIVATE_KEY_13];

const myAddress = '0x2B29A54bc2b62a2BADf1C2090A07Db84f19976DB';

async function sendTokens(to) {
  var amount = "5000000000000";
  const tx = await myERC.transfer(to, amount);
  await tx.wait();
  console.log(tx)
}

async function sendEth(to, i) {
  const wallet = new Wallet(privateKey);
  console.log(wallet)
  const nonce = await alchemy.core.getTransactionCount(
    wallet.address,
    "latest"
  );
  let transaction = {
    to: to,
    value: Utils.parseEther("0.01"),
    gasLimit: "21000",
    maxPriorityFeePerGas: Utils.parseUnits("5", "gwei"),
    maxFeePerGas: Utils.parseUnits("20", "gwei"),
    nonce: nonce,
    type: 2,
    chainId: 11155111,
  };
  let rawTransaction = await wallet.signTransaction(transaction);
  let tx = await alchemy.core.sendTransaction(rawTransaction);
  await tx.wait();
  console.log("Sent transaction", tx);
}


async function sendTokensLoop() {
  for (let i = 0; i <= addresses.length;) {
    console.log("STAGE", i)
    if (i == addresses.length) {
      console.log('SCRIPT IS FINISHED')
      break;
    } else {
      const tx = await sendEth(addresses[i])
      .then(res => {
        i++;
      })
    }
  }
}

sendTokensLoop();
