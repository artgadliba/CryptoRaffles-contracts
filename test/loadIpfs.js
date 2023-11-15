import { create } from 'ipfs-http-client'
import { Buffer } from 'buffer'

import { createRequire } from "module";
const require = createRequire(import.meta.url);
const fs = require('fs');

require("dotenv").config();

/* configure Infura auth settings */
const projectId = process.env.INFURA_IPFS_PROJECT_ID;
const projectSecret = process.env.IFURA_IPFS_SECRET;
const auth = 'Basic ' + Buffer.from(projectId + ':' + projectSecret).toString('base64')

const imgfolder = "/Users/hero/Documents/NFT-sample/images";

/* Create an instance of the client */
const client = create({
  host: 'ipfs.infura.io',
  port: 5001,
  protocol: 'https',
  headers: {
      authorization: auth
  }
});

async function uploadFile(fp) {
  try {
      const img = fs.readFileSync(fp);
      const added = await client.add(img)
      const url = `https://infura-ipfs.io/ipfs/${added.path}`
      const tokenId = fp.replace(/\D/g, "");
      const fileName = `/Users/hero/Documents/NFT-sample/metadata/sample.json`;
      const file = require(fileName);
      file.image = url
      file.name = `CryptoRaffles test collection #${tokenId}`
      const newFileName = `/Users/hero/Documents/NFT-sample/metadata/tokenID_${tokenId}.json`;
      fs.writeFile(newFileName, JSON.stringify(file, null, 2), function writeJSON(err) {
        if (err) return console.log(err);
        console.log('writing to ' + newFileName);
      });
      console.log("IPFS URI: ", url)
  } catch (error) {
    console.log('Error uploading file: ', error)
  }
}

fs.readdir(imgfolder, (err, files) => {
  const filesSorted = files.sort();
  uploadLoop(filesSorted);
})


async function uploadLoop(files) {
  for (let i = 0; i <= files.length;) {
    if (i == files.length) {
      console.log("Script finished")
      break;
    }
    const filepath = `/Users/hero/Documents/NFT-sample/images/${files[i]}`
    await uploadFile(filepath)
    .then(res => {
      i++;
    })
  }
}
