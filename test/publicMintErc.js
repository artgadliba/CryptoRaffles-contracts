import { createRequire } from "module";
import { setTimeout } from "timers/promises";
const require = createRequire(import.meta.url);

const Web3 = require("web3");

const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
const ercAbi = require("../abi/ERC20token_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;

const web3 = createAlchemyWeb3("wss://eth-sepolia.g.alchemy.com/v2/D-7jdz-GDlNmGqStzuAK9w2kH5I0mpDq");

const factoryAddress = "0x4440aeBE9C78Ef22546e36eeC9AdCd98175793fA";
const rafflesAddress = "0xd372e75AEE304845a30c117E7c610B2a1bE93a2F";
const ercAddress = "0xFcc09DEB3Ce135d58ED0c4e7c6D8b59790A9a03b";
const myFactory = new web3.eth.Contract(factoryAbi, factoryAddress);
const myRaffle = new web3.eth.Contract(rafflesAbi, rafflesAddress);
const myERC = new web3.eth.Contract(ercAbi, ercAddress);

const addresses = ['0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8', '0x01299e30c37778B210b6b196fDEB3cB82F37227E', '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96', '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D', '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98', '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83', '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b', '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac', '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB', '0x05B368b1d8672d4c9001B635c5b03235508F83F8', '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792', '0xe97dEE2eeec1189365FCb05d619234e39838522c', '0xC46aab22487F0A67A17997bE1E9979588692fBf1'];

const privateKeys = [process.env.PRIVATE_KEY_1, process.env.PRIVATE_KEY_2, process.env.PRIVATE_KEY_3, process.env.PRIVATE_KEY_4, process.env.PRIVATE_KEY_5, process.env.PRIVATE_KEY_6, process.env.PRIVATE_KEY_7, process.env.PRIVATE_KEY_8, process.env.PRIVATE_KEY_9, process.env.PRIVATE_KEY_10, process.env.PRIVATE_KEY_11, process.env.PRIVATE_KEY_12, process.env.PRIVATE_KEY_13];

async function publicMintErc() {

  const amount = 3;
  const msgValue = "300000000";
  const token = "0xFcc09DEB3Ce135d58ED0c4e7c6D8b59790A9a03b";
  const [v, r, s] = ["0", "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"];

  for (let i = 0; i <= addresses.length; i ++) {

    if (i == addresses.length) {
      console.log('MINT IS FINISHED')
    } else {

      var myAddress = addresses[i];
      console.log(myAddress)
      await approve(myAddress, i, msgValue);
      console.log("TIMEOUT")
      await setTimeout(60000);
      var success_stage1 = false;
      try {
        var gasEstimate = await myRaffle.methods.publicMint(token, msgValue, amount).estimateGas({from: myAddress});
        console.log("Gas estimate:", gasEstimate);
        success_stage1 = true;
      } catch (error) {
        console.log(error);
      } if (success_stage1) {

        let nonce = await web3.eth.getTransactionCount(myAddress, 'latest');
        console.log(nonce);
        let maxPriorityFeePerGasEstimate = await web3.eth.getMaxPriorityFeePerGas();
        console.log(maxPriorityFeePerGasEstimate);

        const tx = {
            from: myAddress,
            to: rafflesAddress,
            value: 0,
            gas: gasEstimate,
            maxPriorityFeePerGas: maxPriorityFeePerGasEstimate,
            nonce: nonce,
            // this encodes the ABI of the method and the arguements
            data: myRaffle.methods.publicMint(token, msgValue, amount).encodeABI()
          };

        const signedTx = await web3.eth.accounts.signTransaction(tx, privateKeys[i]);
        console.log(signedTx);

        var success_stage2 = false;
        try{
          await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
          success_stage2 = true;
        } catch (error) {
          console.log("❗Something went wrong while submitting your transaction:", error);
        } if (success_stage2) {
          console.log("🎉 The hash of your transaction is: ", signedTx.transactionHash, "\n Check Sepolia Etherscan to view the status of your transaction!");
        }
      }
    }
  }
}

async function approve(sender, i, msgValue) {

  var gasEstimate = await myERC.methods.approve(factoryAddress, msgValue).estimateGas({from: sender});
  console.log("Gas estimate:", gasEstimate);

  let nonce = await web3.eth.getTransactionCount(sender, 'latest');
  console.log(nonce);
  let maxPriorityFeePerGasEstimate = await web3.eth.getMaxPriorityFeePerGas();
  console.log(maxPriorityFeePerGasEstimate);

  const tx = {
      from: sender,
      to: ercAddress,
      value: 0,
      gas: gasEstimate,
      maxPriorityFeePerGas: maxPriorityFeePerGasEstimate,
      nonce: nonce,
      // this encodes the ABI of the method and the arguements
      data: myERC.methods.approve(factoryAddress, msgValue).encodeABI()
    };

  const signedTx = await web3.eth.accounts.signTransaction(tx, privateKeys[i]);
  console.log(signedTx);

  web3.eth.sendSignedTransaction(signedTx.rawTransaction, function(error, hash) {
    if (!error) {
      console.log("🎉 The hash of your transaction is: ", hash, "\n Check Sepolia Etherscan to view the status of your transaction!");
    } else {
      console.log("❗Something went wrong while submitting your transaction:", error)
    }
  });
}


async function ownerOf() {
  const _raffleAddress = "0xe8420e24B7A9e15E305a033EC9D7819347e2cA05";
  const myRaffleContract = new web3.eth.Contract(rafflesAbi, _raffleAddress);
  myRaffleContract.methods.ownerOf(1).call()
  .then(result => {
    console.log(result);
  })
}

ownerOf();
