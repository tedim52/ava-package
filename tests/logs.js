const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

// Path to the ABI file (JSON)
const abiPath = path.join(__dirname, 'TokenHome.json');

// Read the ABI file
fs.readFile(abiPath, 'utf8', (err, data) => {
  if (err) {
    console.error("Error reading ABI file:", err);
    return;
  }

  // Parse the ABI JSON
  const abi = JSON.parse(data);

  // Setup a dummy provider (you can replace this with a real provider)
  const provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:9650/ext/bc/wHecoyr8AicbMRp2szEXXcFocKvdmFqWiMXfpb9jpFFq3pU8H/rpc');

  // Replace with the address of your smart contract
  const contractAddress = '0xB5f5A23BBD1Bee9ed105aBA8aC9eCd19f50bB378';

  // Create a contract instance
  const contract = new ethers.Contract(contractAddress, abi.abi, provider);

  // Example log data to decode (the log object with topics and data)
  const log = {
    topics: [
      "0xf229b02a51a4c8d5ef03a096ae0dd727d7b48b710d21b50ebebb560eef739b90",
      "0x88f7f9314088ddc30836e030f133449d960f9ded9362d8f9c0125e52fc9f1fdf",
      "0x000000000000000000000000d603ac7b03c25d45d9525fb7c5fae18b6dda82a0"
    ],
    data: "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012"
  };

  // Decode log using ethers.Contract's `interface`
  try {
    const decodedEvent = contract.interface.parseLog(log);
    console.log("Decoded Event:", decodedEvent);
  } catch (err) {
    console.error("Error decoding log:", err);
  }
});
