import axios from "axios";
import { ethers } from "ethers";

import { createRequire } from "module";
const require = createRequire(import.meta.url);

const crypto = require('crypto');

require("dotenv").config();

const walletList = [];
const addresses = [];

function generateAddresses() {
  for (let i = 0; i < 50000; i++) {
    var id = crypto.randomBytes(32).toString('hex');
    var pvtKey = "0x"+id;
    var wallet = new ethers.Wallet(pvtKey);
    walletList.push(wallet);
    console.log(i)
  }

  for (let n = 0; n < walletList.length; n ++) {
    let walletObj = walletList[n];
    let wallet = walletObj.address;
    addresses.push(wallet);
    console.log('addr', n)
  }
}

generateAddresses();

function registerWallet() {
  function next() {
    let wallet = addresses.shift();
    let raffleId = addresses.shift();

    axios.post('/api/raffles-registry/', {
      wallet: wallet,
      raffle_id: raffleId
    }, {
      headers: {
        Authorization: "Api-Key " + apiKey
      }
    })
    .then(resp => {
      console.log(resp);
    })
    .catch(err => {
      console.log(err);
    })
    if (addresses.length > 0) {
      console.log('next')
      setTimeout(next, 25);
    }
  }
  next();
}

registerWallet();
