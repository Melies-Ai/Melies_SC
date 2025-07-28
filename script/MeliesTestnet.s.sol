// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Melies} from "../src/Melies.sol";
import {MeliesICO} from "../src/MeliesICO.sol";
import {MeliesTokenDistributor} from "../src/MeliesTokenDistributor.sol";
import {MeliesStaking} from "../src/MeliesStaking.sol";

contract MeliesTestnetScript is Script {
    Melies public meliesToken;
    MeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
    MeliesStaking public meliesStaking;

    // Base Sepolia Testnet Contract Addresses
    address constant USDC_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on Base Sepolia from https://docs.base.org/docs/tools/node-providers/
    address constant UNISWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4; // Uniswap V2 Router on Base Sepolia
    address constant CHAINLINK_AGGREGATOR = 0xf9B8fc078197181C841c296C876945aaa425B278; // ETH/USD Price Feed on Base Sepolia from https://docs.chain.link/data-feeds/price-feeds/addresses?network=base&page=1

    // Add addresses for token distribution - Replace with actual testnet addresses
    address constant COMMUNITY_ADDRESS = 0x1111111111111111111111111111111111111111; // Replace with actual testnet address
    address constant TREASURY_ADDRESS = 0x2222222222222222222222222222222222222222; // Replace with actual testnet address
    address constant PARTNERS_ADDRESS = 0x3333333333333333333333333333333333333333; // Replace with actual testnet address
    address constant TEAM_ADDRESS = 0x4444444444444444444444444444444444444444; // Replace with actual testnet address
    address constant LIQUIDITY_ADDRESS = 0x5555555555555555555555555555555555555555; // Replace with actual testnet address
    address constant AI_SYSTEMS_ADDRESS = 0x6666666666666666666666666666666666666666; // Replace with actual testnet address

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address defaultAdmin = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Melies token
        meliesToken = new Melies(defaultAdmin);
        console.log("Melies token deployed at:", address(meliesToken));

        // Deploy TokenDistributor first
        tokenDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            defaultAdmin,
            COMMUNITY_ADDRESS,
            TREASURY_ADDRESS,
            PARTNERS_ADDRESS,
            TEAM_ADDRESS,
            LIQUIDITY_ADDRESS,
            AI_SYSTEMS_ADDRESS
        );
        console.log("TokenDistributor deployed at:", address(tokenDistributor));

        // Deploy MeliesICO with tokenDistributor address
        meliesICO = new MeliesICO(
            address(meliesToken), address(tokenDistributor), USDC_TOKEN, UNISWAP_ROUTER, CHAINLINK_AGGREGATOR
        );
        console.log("MeliesICO deployed at:", address(meliesICO));

        // Deploy MeliesStaking
        meliesStaking = new MeliesStaking(address(meliesToken));
        console.log("MeliesStaking deployed at:", address(meliesStaking));

        // Grant MINTER_ROLE to contracts
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(tokenDistributor));
        console.log("MINTER_ROLE granted to MeliesICO and TokenDistributor");

        // Grant ICO_ROLE to ICO contract in TokenDistributor
        tokenDistributor.grantRole(tokenDistributor.ICO_ROLE(), address(meliesICO));
        console.log("ICO_ROLE granted to MeliesICO in TokenDistributor");

        vm.stopBroadcast();

        // Serialize deployment addresses to JSON
        string memory json = vm.serializeAddress("testnet_deployment", "meliesAddress", address(meliesToken));
        json = vm.serializeAddress("testnet_deployment", "meliesICOAddress", address(meliesICO));
        json = vm.serializeAddress("testnet_deployment", "tokenDistributorAddress", address(tokenDistributor));
        json = vm.serializeAddress("testnet_deployment", "meliesStakingAddress", address(meliesStaking));
        vm.writeJson(json, "./testnet_deployment.json");
    }
}
