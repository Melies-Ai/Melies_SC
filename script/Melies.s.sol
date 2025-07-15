// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Melies} from "../src/Melies.sol";
import {MeliesICO} from "../src/MeliesICO.sol";
import {MeliesTokenDistributor} from "../src/MeliesTokenDistributor.sol";
import {MeliesStaking} from "../src/MeliesStaking.sol";

contract MeliesScript is Script {
    Melies public meliesToken;
    MeliesICO public meliesICO;
    MeliesTokenDistributor public tokenDistributor;
    MeliesStaking public meliesStaking;

    address constant USDC_TOKEN = 0x4444444444444444444444444444444444444444; // Replace with actual USDC address
    address constant USDT_TOKEN = 0x5555555555555555555555555555555555555555; // Replace with actual USDT address
    address constant UNISWAP_ROUTER =
        0x6666666666666666666666666666666666666666; // Replace with actual Uniswap Router address
    address constant CHAINLINK_AGGREGATOR =
        0x7777777777777777777777777777777777777777; // Replace with actual Chainlink ETH/USD Price Feed address

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
        uint256 initialTgeTimestamp = block.timestamp + 30 days; // Replace with actual TGE
        address defaultAdmin = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Melies token
        meliesToken = new Melies(defaultAdmin);
        console.log("Melies token deployed at:", address(meliesToken));

        // Deploy TokenDistributor first
        tokenDistributor = new MeliesTokenDistributor(
            address(meliesToken),
            initialTgeTimestamp,
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
            address(meliesToken),
            address(tokenDistributor),
            USDC_TOKEN,
            USDT_TOKEN,
            UNISWAP_ROUTER,
            CHAINLINK_AGGREGATOR,
            initialTgeTimestamp
        );
        console.log("MeliesICO deployed at:", address(meliesICO));

        // Deploy MeliesStaking
        meliesStaking = new MeliesStaking(
            address(meliesToken),
            uint32(initialTgeTimestamp)
        );
        console.log("MeliesStaking deployed at:", address(meliesStaking));

        // Grant MINTER_ROLE to contracts
        meliesToken.grantRole(meliesToken.MINTER_ROLE(), address(meliesICO));
        meliesToken.grantRole(
            meliesToken.MINTER_ROLE(),
            address(tokenDistributor)
        );
        console.log("MINTER_ROLE granted to MeliesICO and TokenDistributor");

        // Grant ICO_ROLE to ICO contract in TokenDistributor
        tokenDistributor.grantRole(
            tokenDistributor.ICO_ROLE(),
            address(meliesICO)
        );
        console.log("ICO_ROLE granted to MeliesICO in TokenDistributor");

        // Alternative: ICO can grant role to itself (requires admin role in ICO)
        // meliesICO.grantIcoRole();

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
        json = vm.serializeAddress(
            "deployment",
            "tokenDistributorAddress",
            address(tokenDistributor)
        );
        json = vm.serializeAddress(
            "deployment",
            "meliesStakingAddress",
            address(meliesStaking)
        );
        vm.writeJson(json, "./deployment.json");
    }
}
