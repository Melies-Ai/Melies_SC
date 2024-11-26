// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Melies} from "../src/Melies.sol";
import {MeliesICO} from "../src/MeliesICO.sol";

contract MeliesScript is Script {
    Melies public meliesToken;
    MeliesICO public meliesICO;

    address constant USDC_TOKEN = 0x4444444444444444444444444444444444444444; // Replace with actual USDC address
    address constant USDT_TOKEN = 0x5555555555555555555555555555555555555555; // Replace with actual USDT address
    address constant UNISWAP_ROUTER =
        0x6666666666666666666666666666666666666666; // Replace with actual Uniswap Router address
    address constant CHAINLINK_AGGREGATOR =
        0x7777777777777777777777777777777777777777; // Replace with actual Chainlink ETH/USD Price Feed address

    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Melies contract
        address defaultAdmin = vm.addr(deployerPrivateKey);
        uint256 initialTgeTimestamp = block.timestamp + 30 days; // Example: TGE in 30 days

        meliesToken = new Melies(defaultAdmin);

        console.log("Melies token deployed at:", address(meliesToken));

        // Deploy MeliesICO contract
        meliesICO = new MeliesICO(
            address(meliesToken),
            USDC_TOKEN,
            USDT_TOKEN,
            UNISWAP_ROUTER,
            CHAINLINK_AGGREGATOR,
            initialTgeTimestamp
        );

        console.log("MeliesICO deployed at:", address(meliesICO));

        // Grant MINTER_ROLE to MeliesICO
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));

        console.log("MINTER_ROLE granted to MeliesICO");

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Serialize deployment addresses to JSON
        string memory json = vm.serializeAddress(
            "deployment",
            "meliesAddress",
            address(meliesToken)
        );
        json = vm.serializeAddress(
            "deployment",
            "meliesICOAddress",
            address(meliesICO)
        );
        vm.writeJson(json, "./deployment.json");
    }
}
