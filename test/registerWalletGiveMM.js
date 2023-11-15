import express from "express";
import axios from "axios";

import { createRequire } from "module";
const require = createRequire(import.meta.url);

require("dotenv").config();

const app = express();

app.listen(3400, function() {
    console.log("Node server is listening on port 3400...");
});

const apiKey = process.env.REST_API_KEY;

const addresses = ['0x80Db9F69FE3B8A74eA1445424340d5eb5EbCE0F8', '0x01299e30c37778B210b6b196fDEB3cB82F37227E', '0xE78a546197462Ff2b874abe7Af1fCFbb6EdB9e96', '0x2D319C6d6c66b05B99E2e8aF3692482ba467f13D', '0x8C630b4bC1F6e73D2E70F69B23D10cd3A5489D98', '0x49431e8FE8Eb0F695ce7189f5dfD1f521a519E83', '0x1e392bbb45fdcA8E3A8e26e887de96170C715d4b', '0x9D16dC2cFed5FA4f76b34DDb21f0a5aF24aAAdac', '0x3B314dF6347c17a0C9Fd41Ea518f0656980075CB', '0x05B368b1d8672d4c9001B635c5b03235508F83F8', '0xa2a8B1E40240A5A1163B7D48BFd6113CD64e6792', '0xe97dEE2eeec1189365FCb05d619234e39838522c', '0xC46aab22487F0A67A17997bE1E9979588692fBf1'];

function makeid(length) {
    let result = '';
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    const charactersLength = characters.length;
    let counter = 0;
    while (counter < length) {
      result += characters.charAt(Math.floor(Math.random() * charactersLength));
      counter += 1;
    }
    return result;
}

async function registerWallet(i) {
  if (i > addresses.length) {
    i = i % addresses.length
  }
  let wallet = addresses[i];
  const channelId = makeid(12);
  const link = `https://www.youtube.com/channel/${channelId}`;
  axios.post('/api/giveaways-registry/', {
    wallet: wallet,
    giveaway_id: "0xE9749F9fAbE5413C8bF1D4e2c6aCA98D645F821e", // Giveaway type raffle
    social_link: link
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
}

var i = 1;  

function myLoop() {    
  setTimeout(function() {  
    registerWallet(i - 1);  
    console.log(i - 1)
    i++;                    
    if (i < 500000) {         
      myLoop();             
    }                       
  }, 100)
}

myLoop();
