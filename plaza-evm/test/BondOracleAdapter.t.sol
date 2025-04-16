// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Utils} from "../src/lib/Utils.sol";
import {Decimals} from "../src/lib/Decimals.sol";
import {BondOracleAdapter} from "../src/BondOracleAdapter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICLPool} from "../src/lib/concentrated-liquidity/ICLPool.sol";
import {ICLFactory} from "../src/lib/concentrated-liquidity/ICLFactory.sol";
import {ICLPoolDerivedState} from "../src/lib/concentrated-liquidity/ICLPoolDerivedState.sol";

contract BondOracleAdapterTest is Test {
  using Decimals for uint256;
  
  BondOracleAdapter private adapter;
  address private bondToken = address(0x1);
  address private liquidityToken = address(0x2);
  address private dexFactory = address(0x3);
  address private dexPool = address(0x4);
  address private deployer = address(0x5);
  uint32 private twapInterval = 1800; // 30 minutes

  function setUp() public {
    vm.startPrank(deployer);

    // Mock IERC20 decimals calls
    vm.mockCall(
      liquidityToken,
      abi.encodeWithSelector(ERC20.decimals.selector),
      abi.encode(uint8(6))
    );

    vm.mockCall(
      bondToken,
      abi.encodeWithSelector(ERC20.decimals.selector),
      abi.encode(uint8(18))
    );

    // Mock IERC20 symbol calls for description
    vm.mockCall(
      bondToken,
      abi.encodeWithSelector(ERC20.symbol.selector),
      abi.encode("BOND")
    );
    vm.mockCall(
      liquidityToken,
      abi.encodeWithSelector(ERC20.symbol.selector),
      abi.encode("ETH")
    );

    // Mock factory getPool call
    vm.mockCall(
      dexFactory,
      abi.encodeWithSelector(ICLFactory.getPool.selector, bondToken, liquidityToken, 1),
      abi.encode(dexPool)
    );

    // Mock factory tickSpacingToFee call
    vm.mockCall(
      dexFactory,
      abi.encodeWithSignature("tickSpacingToFee(int24)", 1),
      abi.encode(uint24(100))
    );

    vm.mockCall(
      dexPool,
      abi.encodeWithSelector(ICLPool.token1.selector),
      abi.encode(liquidityToken)
    );

    // Deploy and initialize BondOracleAdapter
    adapter = BondOracleAdapter(Utils.deploy(
      address(new BondOracleAdapter()),
      abi.encodeCall(BondOracleAdapter.initialize, (
        bondToken,
        liquidityToken,
        twapInterval,
        dexFactory,
        deployer
      ))
    ));

    vm.stopPrank();
  }

  // "Normally" ordered tokens in pool
  function testLatestRoundDataWethUsdc() public {
    // Mock observe call on pool. tickCumulatives taken for Weth/Usdc from Aerodrome (Base mainnet), March 21 2025
    int56[] memory tickCumulatives = new int56[](2);
    tickCumulatives[0] = -5494264570026; // tick at t-30min
    tickCumulatives[1] = -5494625443032; // tick at t-0
    uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

    vm.mockCall(
      dexPool,
      abi.encodeWithSelector(ICLPoolDerivedState.observe.selector),
      abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
    );

    // Get latest round data
    (,int256 answer,,,) = adapter.latestRoundData();

    // Verify the returned values
    assertEq(answer, 1965542316); // $1965.542316 USDC per WETH
  }

  // Inverted pool
  function testLatestRoundDataUsdcAero() public {
    // The USDC/AERO pool is an inverted pool, so need to set isPoolInverted to true
    // Do this by modifying storage slot directly. isPoolInverted is the 169th bit in the storage slot
    bytes32 value = vm.load(address(adapter), bytes32(uint256(3)));
    assembly {
        // Clear the bool bit (bit 168)
        value := and(value, not(shl(168, 1)))

        // Set the new bool value
        value := or(value, shl(168, true))
    }
    vm.store(address(adapter), bytes32(uint256(3)), value);

    // Mock observe call on pool. tickCumulatives taken for USDC/AERO from Aerodrome (Base mainnet), March 21 2025
    int56[] memory tickCumulatives = new int56[](2);
    tickCumulatives[0] = 7096679348318; // tick at t-30min
    tickCumulatives[1] = 7097188969772; // tick at t-0
    uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
    
    vm.mockCall(
      dexPool,
      abi.encodeWithSelector(ICLPoolDerivedState.observe.selector),
      abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
    );

    // Get latest round data
    (,int256 answer,,,) = adapter.latestRoundData();

    // Verify the returned values
    assertEq(answer, 506686); // $0.506686 USDC per AERO
  }

  function testDescription() public view {
    string memory desc = adapter.description();
    assertEq(desc, "BOND/ETH Oracle Price");
  }

  function testVersion() public view {
    assertEq(adapter.version(), 1);
  }

  function testDecimals() public view {
    assertEq(adapter.decimals(), 6);
  }
}
