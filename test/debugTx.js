import { createRequire } from "module";
const require = createRequire(import.meta.url);

import { ethers } from "ethers";
const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
const ercAbi = require("../abi/ERC20token_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;
const apiURL = process.env.API_URL;

const provider = new ethers.providers.JsonRpcProvider(apiURL);
const signer = new ethers.Wallet(privateKey, provider);

const factoryAddress = "0x8fa446594189307e215005c1681A9961CED02e42";
const rafflesAddress = "";
const ercAddress = "";

const myFactory = new ethers.Contract(factoryAddress, factoryAbi, signer);

async function createRaffle() {
    const settings = ["0x2B29A54bc2b62a2BADf1C2090A07Db84f19976DB", "0x0000000000000000000000000000000000000000", "true", "100000000", "1687429022", "80", "8", "1", "3", "12"];
    const name = "Golden Raffle";
    const symbol = "GLDN";
    const uri = "https://bafybeidr5m5admkkhcr7drwluyy5cjlmaunrcg2hfbw2wcg2n6nsf6no24.ipfs.w3s.link/metadata/tokenID_";

    const tx = await myFactory.createNewRaffle(settings, name, symbol, uri);
    await tx.wait();
    console.log(tx);
}

createRaffle();