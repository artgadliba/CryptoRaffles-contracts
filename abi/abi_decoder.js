import { createRequire } from "module";
const require = createRequire(import.meta.url);

const abiDecoder = require('abi-decoder');

const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
const giveFactoryAbi = require("../abi/RaffleFactoryV2_abi.json");
const giveAbi = require("../abi/CryptoRafflesV2_abi.json");
const vrfAbi = require("../abi/vrfAbi.json");

abiDecoder.addABI(factoryAbi);
abiDecoder.addABI(rafflesAbi);
abiDecoder.addABI(vrfAbi);
abiDecoder.addABI(giveFactoryAbi);
abiDecoder.addABI(giveAbi);

const testData = "0x8b08df70";

const decoded = abiDecoder.decodeMethod(testData);

console.log(decoded);
