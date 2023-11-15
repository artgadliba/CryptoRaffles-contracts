import express from "express";
import axios from "axios";
import { ethers } from "ethers";
import { MerkleTree } from "merkletreejs";
import keccak256 from "keccak256";

import { createRequire } from "module";
const require = createRequire(import.meta.url);

const { createAlchemyWeb3 } = require("@alch/alchemy-web3");

const factoryAbi = require("./abi/CryptoFactoryV1_abi.json");
const raffleAbi = require("./abi/CryptoRafflesV1_abi.json");
const factoryGiveAbi = require("./abi/RaffleFactoryV2_abi.json");

require("dotenv").config();

const app = express();

app.listen(3300, function() {
    console.log("Node server is listening on port 3300...");
});

const apiKey = process.env.REST_API_KEY;
const apiURL = process.env.API_URL;

const web3 = createAlchemyWeb3(apiURL);

const factoryAddress = "0x2612fC96119Df2d88c5Be25dDd1276B06c7a763D";
const myRaffleFactory = new web3.eth.Contract(factoryAbi, factoryAddress);

const factoryGiveAddress = "0xe6C6Fd31394b6494210573511a5d76a4B228c7B5";
const myGiveFactory = new web3.eth.Contract(factoryGiveAbi, factoryGiveAddress);

const optionsCurrent = {
  fromBlock: 3725000
};

async function generateMerkleTree(raffle) {
  const whitelist = [];
  axios.get(`/api/giveaways-registry/${raffle}/`)
  .then(res => {
    let data = res.data;
    for (let i = 0; i < data.length; i ++) {
      let participant = {
        address: data[i].wallet,
        tokenId: i + 1
      };
      whitelist.push(participant);
    }
    const leaves = whitelist.map((x) =>
      ethers.utils.solidityKeccak256(
        ["address", "uint256"],
        [x.address, x.tokenId]
      )
    );
    const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true })
    const merkleRootHash = merkleTree.getHexRoot()
    axios.post(`/api/giveaways/${raffle}/`, {
      root: merkleRootHash
    }, {
      headers: {
        Authorization: "Api-Key " + apiKey
      }
    })
    .then(function (response) {
      console.log(response);
    })
    .catch(function (error) {
      console.log(error);
    })
    setTimeout(generateMerkleProof, 300000, raffle, merkleTree); // 5 minutes timeout before generation of merkle proof
  })
}

async function generateMerkleProof(raffle, merkleTree) {
  axios.get(`/api/giveaways/${raffle}/`)
  .then(res => {
    let data = res.data[0];
    let grandPrizeWinners = data.grand_prize_winners;
    let grandPrizeTokens = data.grand_prize_tokens;
    let minorPrizeWinners = data.minor_prize_winners;
    let minorPrizeTokens = data.minor_prize_tokens;
    if (grandPrizeWinners != undefined) {
      for (let i = 0; i < grandPrizeWinners.length; i ++) {
        let grandLeaf =
          ethers.utils.solidityKeccak256(
            ["address", "uint256"],
            [grandPrizeWinners[i], grandPrizeTokens[i]]
          );
        let grandPrizeProof = merkleTree.getHexProof(grandLeaf);
        axios.post('/api/merkles/', {
          wallet: grandPrizeWinners[i],
          giveaway_id: raffle,
          proof: grandPrizeProof
        }, {
          headers: {
            Authorization: "Api-Key " + apiKey
          }
        })
        .then(function (response) {
          console.log(response);
        })
        .catch(function (error) {
          console.log(error);
        })
      }
    }
    if (minorPrizeWinners != undefined) {
      for (let i = 0; i < minorPrizeWinners.length; i ++) {
        let minorLeaf =
          ethers.utils.solidityKeccak256(
            ["address", "uint256"],
            [minorPrizeWinners[i], minorPrizeTokens[i]]
          );
        let minorPrizeProof = merkleTree.getHexProof(minorLeaf);
        axios.post('/api/merkles/', {
          wallet: minorPrizeWinners[i],
          giveaway_id: raffle,
          proof: minorPrizeProof
        }, {
          headers: {
            Authorization: "Api-Key " + apiKey
          }
        })
        .then(function (response) {
          console.log(response);
        })
        .catch(function (error) {
          console.log(error);
        })
      }
    }
  })
}

myRaffleFactory.events.allEvents(optionsCurrent)
      .on('data', event => {
        if (event.event == "RaffleCreated") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          let grandPrizeMargin = result["grandPrizeMargin"].toString();
          let minorPrizeMargin = result["minorPrizeMargin"].toString();
          let endTimestamp = result["endTimestamp"] * 1000;
          let numGrandWins = result["numGrandWins"].toString();
          let numBonusWins = result["numBonusWins"].toString();
          let entryFee = result["entryFee"].toString();
          let paytoken = result["paytoken"];
          let fixed = result["_fixed"]
          let treasuryType = 3;
          if (fixed == true) {
            treasuryType = 4;
          }
          let myRaffleContract = new web3.eth.Contract(raffleAbi, raffleAddress);
          myRaffleContract.methods.name().call()
          .then(name => {
            let raffleName = name;
            myRaffleContract.methods.owner().call()
            .then(wallet => {
              let ownerWallet = wallet;
              axios.post('/api/raffles/', {
                raffle_id: raffleAddress,
                owner_wallet: ownerWallet,
                grand_prize_margin: grandPrizeMargin,
                minor_prize_margin: minorPrizeMargin,
                end_timestamp: endTimestamp,
                num_grand_wins: numGrandWins,
                num_bonus_wins: numBonusWins,
                entry_fee: entryFee,
                paytoken: paytoken,
                status: "0", // status OPEN
                treasury_type: treasuryType,
                raffle_name: raffleName
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
            })
          })
      } else if (event.event == "OwnerCharged") {
            let result = event.returnValues;
            let raffleAddress = String(result["raffleAddress"]);
            let amount = result["amount"].toString();
            let owner = result["owner"];
            axios.get(`/api/raffles/${raffleAddress}/`)
            .then(res => {
              let data = res.data[0];
              let grandPrizeMargin = data.grand_prize_margin;
              let minorPrizeMargin = data.minor_prize_margin;
              let numGrandWins = data.num_grand_wins;
              let numBonusWins = data.num_bonus_wins;
              let grandPrize = String(Math.floor((amount * grandPrizeMargin / 100) / numGrandWins));
              let minorPrize = String(Math.floor((amount * minorPrizeMargin / 100) / numBonusWins));
              let prizeFund = String(Math.floor(amount * (grandPrizeMargin + minorPrizeMargin) / 100));
              axios.post(`/api/raffles/${raffleAddress}/`, {
                owner_wallet: owner,
                treasury: prizeFund,
                grand_prize: grandPrize,
                minor_prize: minorPrize,
                owner_charged: true
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
            })
            .catch(err => {
              console.log(err);
            })
        } else if (event.event == "PlayerJoined") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          let player = result["player"];
          let myRaffleContract = new web3.eth.Contract(raffleAbi, raffleAddress);
          myRaffleContract.methods.totalSupply()
          .call()
          .then(supply => {
            let totalSupply = supply;
            axios.get(`/api/raffles/${raffleAddress}/`)
            .then(res => {
              let data = res.data[0];
              let grandPrizeMargin = data.grand_prize_margin;
              let minorPrizeMargin = data.minor_prize_margin;
              let entryFee = data.entry_fee;
              let numGrandWins = data.num_grand_wins;
              let numBonusWins = data.num_bonus_wins;
              let treasuryType = data.treasury_type;
              let prevPrizeFund = data.treasury;
              if (treasuryType == 3) {
                let treasury = totalSupply * entryFee;
                let prizeFund = String(Math.floor(treasury * (grandPrizeMargin + minorPrizeMargin) / 100));
                if (prevPrizeFund != prizeFund) {
                  let grandPrize = String(Math.floor((treasury * grandPrizeMargin / 100) / numGrandWins));
                  let minorPrize = String(Math.floor((treasury * minorPrizeMargin / 100) / numBonusWins));
                  axios.post(`/api/raffles/${raffleAddress}/`, {
                    treasury: prizeFund,
                    grand_prize: grandPrize,
                    minor_prize: minorPrize
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
              }
            })
            .catch(err => {
              console.log(err);
            })
          })
          axios.post('/api/raffles-registry/', {
            wallet: player,
            raffle_id: raffleAddress
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
        } else if (event.event == "PrizeRaffled") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          let grandPrizeTokensRaw = result["grandPrizeTokens"];
          let grandPrizeTokens = grandPrizeTokensRaw.map(String);
          let minorPrizeTokensRaw = result["minorPrizeTokens"];
          let minorPrizeTokens = minorPrizeTokensRaw.map(String);
          let grandPrizeWinners = [];
          let minorPrizeWinners = [];
          for (let i = 0; i < grandPrizeTokens.length; i++) {
            grandPrizeWinners.push(0);
          }
          for (let i = 0; i < minorPrizeTokens.length; i++) {
            minorPrizeWinners.push(0);
          }
          for (let i = 0; i < grandPrizeTokens.length; i++) {
            let currentGrandToken = grandPrizeTokens[i];
            let myRaffleContract = new web3.eth.Contract(raffleAbi, raffleAddress);
            myRaffleContract.methods.ownerOf(currentGrandToken).call()
            .then(grandWinner => {
              grandPrizeWinners.splice(i, 1, grandWinner);
              if (grandPrizeWinners.every(winner => winner != 0)) {
                for (let i = 0; i < minorPrizeTokens.length; i++) {
                  let currentMinorToken = minorPrizeTokens[i];
                  myRaffleContract.methods.ownerOf(currentMinorToken).call()
                  .then(minorWinner => {
                    minorPrizeWinners.splice(i, 1, minorWinner);
                    if (minorPrizeWinners.every(winner => winner != 0)) {
                      axios.post(`/api/raffles/${raffleAddress}/`, {
                        grand_prize_winners: grandPrizeWinners,
                        grand_prize_tokens: grandPrizeTokens,
                        minor_prize_winners: minorPrizeWinners,
                        minor_prize_tokens: minorPrizeTokens,
                        status: 1 // Status RAFFLED
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
                      axios.get(`/api/raffles/${raffleAddress}/`)
                      .then(res => {
                        let data = res.data[0];
                        let grandPrize = data.grand_prize;
                        let paytoken = data.paytoken;
                        let name = data.raffle_name;
                        if (grandPrizeWinners != undefined) {
                          for (let i = 0; i < grandPrizeWinners.length; i++) {
                            let emojis = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
                            let n = 3;
                            let shuffledArray = emojis.sort(() => 0.5 - Math.random());
                            let result = shuffledArray.slice(0, n);
                            axios.post(`/api/winners/`, {
                              wallet: grandPrizeWinners[i],
                              raffle_name: name,
                              prize: grandPrize,
                              paytoken: paytoken,
                              emoji_first: `https://cryptoraffles.io/media/images/${result[0]}.webp`,
                              emoji_second:`https://cryptoraffles.io/media/images/${result[1]}.webp`,
                              emoji_third: `https://cryptoraffles.io/media/images/${result[2]}.webp`
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
                        }
                      })
                      .catch(err => {
                        console.log(err);
                      })
                    }
                  })
                  .catch(err => {
                    console.log(err);
                  })
                }
              }
            })
            .catch(err => {
              console.log(err);
            })
          }
        } else if (event.event == "RaffleCanceled") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          if (raffleAddress != undefined) {
            axios.post(`/api/raffles/${raffleAddress}/`, {
              end_timestamp: Date.now(),
              status: 2 // Status CANCELED
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
        } else if (event.event == "PrizeWithdrawed") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          let player = result["player"];
          axios.get(`/api/raffles/${raffleAddress}/`)
          .then(res => {
            let data = res.data[0];
            let grandPrizeWinners = data.grand_prize_winners;
            let grandPrizeTokens = data.grand_prize_tokens;
            let minorPrizeWinners = data.minor_prize_winners;
            let minorPrizeTokens = data.minor_prize_tokens;
        
            if (grandPrizeWinners != undefined) {
              if (grandPrizeWinners.includes(player)) {
                let index = grandPrizeWinners.indexOf(player);
                axios.post('/api/raffles-withdrawed/', {
                  wallet: player,
                  raffle_id: raffleAddress,
                  token_id: grandPrizeTokens[index]
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
            }
            if (minorPrizeWinners != undefined) {
              if (minorPrizeWinners.includes(player)) {
                let index = minorPrizeWinners.indexOf(player);
                axios.post('/api/raffles-withdrawed/', {
                  wallet: player,
                  raffle_id: raffleAddress,
                  token_id: minorPrizeTokens[index]
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
            }
          })
        } else if (event.event == "OwnerWithdrawed") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          axios.post(`/api/raffles/${raffleAddress}/`, {
            owner_withdrawed: true
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
        } else if (event.event == "EmergencyWithdrawed") {
          let result = event.returnValues;
          let raffleAddress = String(result["raffleAddress"]);
          let player = result["player"];
          axios.post('/api/raffles-withdrawed/', {
            wallet: player,
            raffle_id: raffleAddress,
            token_id: 0
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
      })
      .on('changed', changed => console.log(changed))
      .on('error', err => console.log(err))
      .on('connected', str => console.log(str))

myGiveFactory.events.allEvents(optionsCurrent)
.on('data', event => {
  if (event.event == "RaffleCreated") {
    let result = event.returnValues;
    let raffleAddress = String(result["raffleAddress"]);
    let startTime = result['startTime'] * 1000;
    let endTimestamp = result["endTimestamp"] * 1000;
    let paytoken = result["paytoken"];
    let grandPrizeMargin = result["grandPrizeMargin"].toString();
    let minorPrizeMargin = result["minorPrizeMargin"].toString();
    let numGrandWins = result["numGrandsWins"].toString(); // IN PROD CHANGE TO "numGrandWins"
    let numBonusWins = result["numBonusWins"].toString();
    axios.post('/api/giveaways/', {
      giveaway_id: raffleAddress,
      start_time: startTime,
      end_timestamp: endTimestamp,
      paytoken: paytoken,
      grand_prize_margin: grandPrizeMargin,
      minor_prize_margin: minorPrizeMargin,
      num_grand_wins: numGrandWins,
      num_bonus_wins: numBonusWins,
      status: "0" // status OPEN
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
  } else if (event.event == "OwnerCharged") {
    let result = event.returnValues;
    let raffleAddress = String(result["raffleAddress"]);
    let amount = result["amount"].toString();
    let owner = result["owner"];
    axios.get(`/api/giveaways/${raffleAddress}/`)
    .then(res => {
      let data = res.data[0];
      let grandPrizeMargin = data.grand_prize_margin;
      let minorPrizeMargin = data.minor_prize_margin;
      let numGrandWins = data.num_grand_wins;
      let numBonusWins = data.num_bonus_wins;
      let endTimestamp = data.end_timestamp;
      let grandPrize = String(Math.floor((amount * grandPrizeMargin / 100) / numGrandWins));
      let minorPrize = String(Math.floor((amount * minorPrizeMargin / 100) / numBonusWins));
      let prizeFund = String(Math.floor(amount * (grandPrizeMargin + minorPrizeMargin) / 100));
      let timer = endTimestamp - Date.now();
      if (timer > 0) {
        setTimeout(generateMerkleTree, timer, raffleAddress);
      } else if (timer <= 0 && data.root == undefined) {
        setTimeout(generateMerkleTree, 2000, raffleAddress);
      }
      axios.post(`/api/giveaways/${raffleAddress}/`, {
        owner_wallet: owner,
        treasury: prizeFund,
        owner_charged: true,
        grand_prize: grandPrize,
        minor_prize: minorPrize
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
    })
    .catch(err => {
      console.log(err);
    })
  } else if (event.event == "PrizeRaffled") {
    let result = event.returnValues;
    let raffleAddress = String(result["raffleAddress"]);
    let grandPrizeTokensRaw = result["grandPrizeTokens"];
    let grandPrizeTokens = grandPrizeTokensRaw.map(String);
    let minorPrizeTokensRaw = result["minorPrizeTokens"];
    let minorPrizeTokens = minorPrizeTokensRaw.map(String);
    axios.get(`/api/giveaways-registry/${raffleAddress}/`)
    .then(res => {
      let data = res.data;
      let grandPrizeWinners = [];
      for (let i = 0; i < grandPrizeTokens.length; i ++) {
        let grandPrizeWinnerRaw = data[grandPrizeTokens[i] - 1];
        let grandPrizeWinner = grandPrizeWinnerRaw.wallet;
        grandPrizeWinners.push(grandPrizeWinner);
      }
      let minorPrizeWinners = [];
      for (let i = 0; i < minorPrizeTokens.length; i ++) {
        let minorPrizeWinnerRaw = data[minorPrizeTokens[i] - 1];
        let minorPrizeWinner = minorPrizeWinnerRaw.wallet;
        minorPrizeWinners.push(minorPrizeWinner);
      }
      axios.post(`/api/giveaways/${raffleAddress}/`, {
        grand_prize_tokens: grandPrizeTokens,
        grand_prize_winners: grandPrizeWinners,
        minor_prize_tokens: minorPrizeTokens,
        minor_prize_winners: minorPrizeWinners,
        status: 1 // Status RAFFLED
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
    })
    .catch(err => {
      console.log(err);
    })
    axios.get(`/api/giveaways/${raffleAddress}/`)
    .then(res => {
      let data = res.data[0];
      let grandPrize = data.grand_prize;
      let grandPrizeWinners = data.grand_prize_winners;
      let name = data.giveaway_name;
      let paytoken = data.paytoken;
      let emojis = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
      let n = 3;
      let shuffledArray = emojis.sort(() => 0.5 - Math.random());
      let result = shuffledArray.slice(0, n);
      if (grandPrizeWinners != undefined) {
        for (let i = 0; i < grandPrizeWinners.length; i ++) {
          axios.post(`/api/winners/`, {
            wallet: grandPrizeWinners[i],
            giveaway_name: name,
            prize: grandPrize,
            paytoken: paytoken,
            emoji_first: `https://cryptoraffles.io/media/images/${result[0]}.webp`,
            emoji_second:`https://cryptoraffles.io/media/images/${result[1]}.webp`,
            emoji_third: `https://cryptoraffles.io/media/images/${result[2]}.webp`
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
      }
    })
    .catch(err => {
      console.log(err);
    })
  } else if (event.event == "RaffleCanceled") {
    let result = event.returnValues;
    let raffleAddress = String(result["raffleAddress"]);
    axios.post(`/api/giveaways/${raffleAddress}/`, {
      end_timestamp: Date.now(),
      status: 2 // Status CANCELED
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
  } else if (event.event == "PrizeWithdrawed") {
    let result = event.returnValues;
    let raffleAddress = String(result["raffleAddress"]);
    let player = result["player"];
    axios.post(`/api/giveaways-withdrawed/`, {
      wallet: player,
      giveaway_id: raffleAddress
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
})
.on('changed', changed => console.log(changed))
.on('error', err => console.log(err))
.on('connected', str => console.log(str))