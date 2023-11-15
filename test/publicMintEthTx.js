import { createRequire } from "module";
const require = createRequire(import.meta.url);

const Web3 = require("web3");
const Transaction = require('@ethereumjs/tx').Transaction;

const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const factoryAbi = require("../abi/CryptoFactoryV1_abi.json");
const rafflesAbi = require("../abi/CryptoRafflesV1_abi.json");
require("dotenv").config();

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.PRIVATE_KEY;

const web3 = createAlchemyWeb3("wss://eth-sepolia.g.alchemy.com/v2/D-7jdz-GDlNmGqStzuAK9w2kH5I0mpDq");

const factoryAddress = "0xc739A1EdCEc7c72BBfAc48dEDF69e5B5b6D79C26";
const rafflesAddress = "0x0acEe5CAf7ec6E1939b16220467df96aB002a39F";
const myFactory = new web3.eth.Contract(factoryAbi, factoryAddress);
const myRaffle = new web3.eth.Contract(rafflesAbi, rafflesAddress);

const addresses = ['0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8', '0x01299e30c37778B210b6b196fDEB3cB82F37227E', '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96', '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D', '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98', '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83', '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b', '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac', '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB', '0x05B368b1d8672d4c9001B635c5b03235508F83F8', '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792', '0xe97dEE2eeec1189365FCb05d619234e39838522c', '0xC46aab22487F0A67A17997bE1E9979588692fBf1'];

const privateKeys = [process.env.PRIVATE_KEY_1, process.env.PRIVATE_KEY_2, process.env.PRIVATE_KEY_3, process.env.PRIVATE_KEY_4, process.env.PRIVATE_KEY_5, process.env.PRIVATE_KEY_6, process.env.PRIVATE_KEY_7, process.env.PRIVATE_KEY_8, process.env.PRIVATE_KEY_9, process.env.PRIVATE_KEY_10, process.env.PRIVATE_KEY_11, process.env.PRIVATE_KEY_12, process.env.PRIVATE_KEY_13];

async function publicMintEth(i) {
  const price = 1000000000;
  const amount = 3;
  const token = "0x0000000000000000000000000000000000000000";
  const myAddress = addresses[i];

  myRaffle.methods.publicMint(token, 0, amount).estimateGas({from: myAddress, value: price * amount})
  .then(gasEstimate => {
    console.log("Gas estimate:", gasEstimate);

    web3.eth.getTransactionCount(myAddress, 'latest')
    .then(nonce => {
      console.log(nonce);

      const tx = {
        from: myAddress,
        to: rafflesAddress,
        value: 0,
        gas: gasEstimate + 500,
        maxPriorityFeePerGas: 1500000000,
        nonce: nonce,
        // this encodes the ABI of the method and the arguements
        data: myRaffle.methods.publicMint(token, 0, amount).encodeABI()
      };

      web3.eth.accounts.signTransaction(tx, privateKeys[i])
      .then(signedTx => {
        console.log(signedTx);

        web3.eth.sendSignedTransaction(signedTx.rawTransaction)
        .on('transactionHash', (hash) => {
            console.log('txHash:', hash);

            myRaffle.getPastEvents('Transfer', {
                        filter: {
                            transactionHash: hash,
                            to: myAddress
                        }
                    })
            .then(result => {
              console.log(result);
            })
        })
        .on('error', console.error);
      })
    })
    .catch(err => {
      console.log(err);
    })
  })
  .catch(err => {
    console.log(err);
  })
};

// async function publicMintLoop() {
//   for (let i = 0; i <= addresses.length; i++) {
//     console.log("STAGE", i)
//     if (i == addresses.length) {
//       console.log('SCRIPT IS FINISHED')
//       break;
//     } else {
//       const tx = await publicMintEth(i)
//       .then(res => {
//         i++;
//       })
//     }
//   }
// }

publicMintEth(1);
