// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Melies} from "../src/Melies.sol";

contract MeliesScript is Script {
    Melies public meliesToken;

    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Melies contract
        address defaultAdmin = vm.addr(deployerPrivateKey);
        address pauser = 0x1111111111111111111111111111111111111111;
        address minter = 0x2222222222222222222222222222222222222222;
        address burner = 0x3333333333333333333333333333333333333333;

        meliesToken = new Melies(defaultAdmin, pauser, minter, burner);

        console.log("Melies token deployed at:", address(meliesToken));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        string memory json = vm.serializeAddress("deployment", "meliesAddress", address(meliesToken));
        vm.writeJson(json, "./deployment.json");
    }
}