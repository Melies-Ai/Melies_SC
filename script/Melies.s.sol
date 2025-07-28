// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Melies} from "../src/Melies.sol";
import {MeliesICO} from "../src/MeliesICO.sol";
import {MeliesTokenDistributor} from "../src/MeliesTokenDistributor.sol";
import {MeliesStaking} from "../src/MeliesStaking.sol";

contract MeliesMainnetScript is Script {
    Melies public meliesToken;
    MeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
    MeliesStaking public meliesStaking;

    // Base Mainnet Contract Addresses
    address constant USDC_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base Mainnet from https://developers.circle.com/stablecoins/usdc-contract-addresses
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // Uniswap V3 Swap Router on Base Mainnet from https://docs.uniswap.org/contracts/v3/reference/deployments/base-deployments
    address constant CHAINLINK_AGGREGATOR = 0xf9B8fc078197181C841c296C876945aaa425B278; // ETH/USD Price Feed on Base Mainnet from https://docs.chain.link/chainlink-functions/supported-networks#base-mainnet

    // Add addresses for token distribution
    address constant COMMUNITY_ADDRESS = address(0); // Replace with actual address
    address constant TREASURY_ADDRESS = address(0); // Replace with actual address
    address constant PARTNERS_ADDRESS = address(0); // Replace with actual address
    address constant TEAM_ADDRESS = address(0); // Replace with actual address
    address constant LIQUIDITY_ADDRESS = address(0); // Replace with actual address
    address constant AI_SYSTEMS_ADDRESS = address(0); // Replace with actual address

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
        string memory json = vm.serializeAddress("mainnet_deployment", "meliesAddress", address(meliesToken));
        json = vm.serializeAddress("mainnet_deployment", "meliesICOAddress", address(meliesICO));
        json = vm.serializeAddress("mainnet_deployment", "tokenDistributorAddress", address(tokenDistributor));
        json = vm.serializeAddress("mainnet_deployment", "meliesStakingAddress", address(meliesStaking));
        vm.writeJson(json, "./mainnet_deployment.json");
    }
}
