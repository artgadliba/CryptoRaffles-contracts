import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { Alchemy, Network, Wallet, Utils } = require("alchemy-sdk");
const fs = require("fs-extra");
import { BigNumber, ethers } from "ethers";

const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;
const apiURL = process.env.API_URL;

const provider = new ethers.providers.JsonRpcProvider(apiURL)
const signer = new ethers.Wallet(privateKey, provider);

const factoryAddress = "0x8fa446594189307e215005c1681A9961CED02e42";
const rafflesAddress = "0x2F226Cd4Deb684262DB9f1f6370754F0E4E6Aada";
const myFactory = new ethers.Contract(factoryAddress, factoryAbi, signer);
const myRaffle = new ethers.Contract(rafflesAddress, rafflesAbi, signer);

const addresses = ['0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8', '0x01299e30c37778B210b6b196fDEB3cB82F37227E', '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96', '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D', '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98', '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83', '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b', '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac', '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB', '0x05B368b1d8672d4c9001B635c5b03235508F83F8', '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792', '0xe97dEE2eeec1189365FCb05d619234e39838522c', '0xC46aab22487F0A67A17997bE1E9979588692fBf1'];

const privateKeys = [process.env.PRIVATE_KEY_1, process.env.PRIVATE_KEY_2, process.env.PRIVATE_KEY_3, process.env.PRIVATE_KEY_4, process.env.PRIVATE_KEY_5, process.env.PRIVATE_KEY_6, process.env.PRIVATE_KEY_7, process.env.PRIVATE_KEY_8, process.env.PRIVATE_KEY_9, process.env.PRIVATE_KEY_10, process.env.PRIVATE_KEY_11, process.env.PRIVATE_KEY_12, process.env.PRIVATE_KEY_13];

async function publicMintEth(i) {
  const price = BigNumber.from("100000000000000");
  const amount = 2;
  const token = "0x0000000000000000000000000000000000000000";

  const _signer = new ethers.Wallet(privateKeys[i], provider);
  const _myRaffle = new ethers.Contract(rafflesAddress, rafflesAbi, _signer);

  const tx = await _myRaffle.publicMint(token, 0, amount, {value: price * amount});
  await tx.wait();
  console.log(tx)
}

async function publicMintLoop() {
  for (let i = 0; i <= 100;) {
    console.log("STAGE", i);
    if (i == 100) {
      console.log("Mint finished")
      break;
    }
    if (i >= addresses.length) {
      i = i % addresses.length;
    }
    const tx = await publicMintEth(i)
    .then(res => {
      i++;
    })
  }
}

publicMintLoop();
