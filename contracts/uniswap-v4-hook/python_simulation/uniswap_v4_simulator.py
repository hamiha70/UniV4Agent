import math
from dataclasses import dataclass
from typing import Tuple, Optional
from decimal import Decimal, getcontext

# Set precision for decimal calculations
getcontext().prec = 28

@dataclass
class Tick:
    """Represents a tick in the Uniswap V4 pool"""
    liquidity_net: Decimal
    liquidity_gross: Decimal
    price: Decimal
    index: int

@dataclass
class PoolState:
    """Represents the current state of the Uniswap V4 pool"""
    sqrt_price_x96: Decimal
    tick: int
    liquidity: Decimal
    ticks: dict[int, Tick]
    token0_reserves: Decimal
    token1_reserves: Decimal

class UniswapV4Simulator:
    def __init__(
        self,
        initial_sqrt_price_x96: Decimal,
        tick_spacing: int,
        fee: int = 3000  # 0.3% fee
    ):
        """
        Initialize the Uniswap V4 pool simulator
        
        Args:
            initial_sqrt_price_x96: Initial sqrt price in X96 format
            tick_spacing: Spacing between ticks
            fee: Pool fee in basis points (default: 3000 = 0.3%)
        """
        self.fee = Decimal(fee) / Decimal(10000)  # Convert basis points to decimal
        self.tick_spacing = tick_spacing
        
        # Initialize pool state
        self.state = PoolState(
            sqrt_price_x96=initial_sqrt_price_x96,
            tick=self._sqrt_price_to_tick(initial_sqrt_price_x96),
            liquidity=Decimal('0'),
            ticks={},
            token0_reserves=Decimal('0'),
            token1_reserves=Decimal('0')
        )
        
    def _sqrt_price_to_tick(self, sqrt_price_x96: Decimal) -> int:
        """Convert sqrt price in X96 format to tick"""
        price = (sqrt_price_x96 / Decimal(2**96)) ** 2
        return int(math.log(price, Decimal(1.0001)))
    
    def _tick_to_sqrt_price(self, tick: int) -> Decimal:
        """Convert tick to sqrt price in X96 format"""
        price = Decimal(1.0001) ** tick
        return Decimal(2**96) * Decimal(price).sqrt()
    
    def _get_tick_at_price(self, price: Decimal) -> int:
        """Get the tick at a given price"""
        return int(math.log(price, Decimal(1.0001)))
    
    def _get_nearest_tick(self, tick: int) -> int:
        """Get the nearest valid tick based on tick spacing"""
        return round(tick / self.tick_spacing) * self.tick_spacing
    
    def add_liquidity(
        self,
        tick_lower: int,
        tick_upper: int,
        amount: Decimal
    ) -> Tuple[Decimal, Decimal]:
        """
        Add liquidity to the pool
        
        Args:
            tick_lower: Lower tick boundary
            tick_upper: Upper tick boundary
            amount: Amount of liquidity to add
            
        Returns:
            Tuple of (amount0, amount1) required for the liquidity
        """
        # Ensure ticks are valid
        tick_lower = self._get_nearest_tick(tick_lower)
        tick_upper = self._get_nearest_tick(tick_upper)
        
        # Calculate amounts needed
        sqrt_price_lower = self._tick_to_sqrt_price(tick_lower)
        sqrt_price_upper = self._tick_to_sqrt_price(tick_upper)
        current_sqrt_price = self.state.sqrt_price_x96
        
        # Calculate amounts based on current price position
        if current_sqrt_price <= sqrt_price_lower:
            amount0 = amount * (sqrt_price_upper - sqrt_price_lower) / (sqrt_price_lower * sqrt_price_upper)
            amount1 = Decimal('0')
        elif current_sqrt_price >= sqrt_price_upper:
            amount0 = Decimal('0')
            amount1 = amount * (sqrt_price_upper - sqrt_price_lower)
        else:
            amount0 = amount * (sqrt_price_upper - current_sqrt_price) / (current_sqrt_price * sqrt_price_upper)
            amount1 = amount * (current_sqrt_price - sqrt_price_lower)
        
        # Update pool state
        self.state.liquidity += amount
        self.state.token0_reserves += amount0
        self.state.token1_reserves += amount1
        
        # Update ticks
        if tick_lower not in self.state.ticks:
            self.state.ticks[tick_lower] = Tick(
                liquidity_net=amount,
                liquidity_gross=amount,
                price=self._tick_to_sqrt_price(tick_lower),
                index=tick_lower
            )
        else:
            self.state.ticks[tick_lower].liquidity_net += amount
            self.state.ticks[tick_lower].liquidity_gross += amount
            
        if tick_upper not in self.state.ticks:
            self.state.ticks[tick_upper] = Tick(
                liquidity_net=-amount,
                liquidity_gross=amount,
                price=self._tick_to_sqrt_price(tick_upper),
                index=tick_upper
            )
        else:
            self.state.ticks[tick_upper].liquidity_net -= amount
            self.state.ticks[tick_upper].liquidity_gross += amount
        
        return amount0, amount1
    
    def _compute_swap_step(
        self,
        sqrt_price_x96: Decimal,
        target_sqrt_price_x96: Decimal,
        liquidity: Decimal,
        amount_in: Decimal,
        zero_for_one: bool
    ) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
        """
        Compute the next sqrt price and amount out for a swap step
        
        Returns:
            Tuple of (next_sqrt_price, amount_in, amount_out, fee_amount)
        """
        if zero_for_one:
            # Swap token0 for token1
            amount_in = min(
                amount_in,
                (sqrt_price_x96 - target_sqrt_price_x96) * liquidity / sqrt_price_x96
            )
            next_sqrt_price = sqrt_price_x96 - (amount_in * sqrt_price_x96 / liquidity)
            amount_out = liquidity * (sqrt_price_x96 - next_sqrt_price) / (sqrt_price_x96 * next_sqrt_price)
        else:
            # Swap token1 for token0
            amount_in = min(
                amount_in,
                (target_sqrt_price_x96 - sqrt_price_x96) * liquidity / sqrt_price_x96
            )
            next_sqrt_price = sqrt_price_x96 + (amount_in * sqrt_price_x96 / liquidity)
            amount_out = liquidity * (next_sqrt_price - sqrt_price_x96) / (sqrt_price_x96 * next_sqrt_price)
        
        fee_amount = amount_in * self.fee
        return next_sqrt_price, amount_in, amount_out, fee_amount
    
    def execute_swap(
        self,
        amount_in: Decimal,
        zero_for_one: bool,
        sqrt_price_limit_x96: Optional[Decimal] = None
    ) -> Tuple[Decimal, Decimal, Decimal]:
        """
        Execute a swap in the pool
        
        Args:
            amount_in: Amount of input token
            zero_for_one: True if swapping token0 for token1, False otherwise
            sqrt_price_limit_x96: Optional price limit for the swap
            
        Returns:
            Tuple of (amount_in, amount_out, fee_amount)
        """
        current_sqrt_price = self.state.sqrt_price_x96
        current_tick = self.state.tick
        current_liquidity = self.state.liquidity
        
        # Set price limit if not provided
        if sqrt_price_limit_x96 is None:
            sqrt_price_limit_x96 = (
                Decimal('1') / Decimal(2**96) if zero_for_one
                else Decimal(2**96) * Decimal(2**128)
            )
        
        # Execute swap
        next_sqrt_price, amount_in, amount_out, fee_amount = self._compute_swap_step(
            current_sqrt_price,
            sqrt_price_limit_x96,
            current_liquidity,
            amount_in,
            zero_for_one
        )
        
        # Update pool state
        self.state.sqrt_price_x96 = next_sqrt_price
        self.state.tick = self._sqrt_price_to_tick(next_sqrt_price)
        
        # Update reserves
        if zero_for_one:
            self.state.token0_reserves += amount_in
            self.state.token1_reserves -= amount_out
        else:
            self.state.token0_reserves -= amount_out
            self.state.token1_reserves += amount_in
        
        return amount_in, amount_out, fee_amount
    
    def get_current_price(self) -> Decimal:
        """Get the current price of token1 in terms of token0"""
        return (self.state.sqrt_price_x96 / Decimal(2**96)) ** 2
    
    def get_reserves(self) -> Tuple[Decimal, Decimal]:
        """Get the current reserves of both tokens"""
        return self.state.token0_reserves, self.state.token1_reserves

def main():
    # Example usage
    initial_sqrt_price = Decimal(2**96)  # 1:1 price
    tick_spacing = 60  # Standard tick spacing
    
    # Create pool simulator
    pool = UniswapV4Simulator(
        initial_sqrt_price_x96=initial_sqrt_price,
        tick_spacing=tick_spacing
    )
    
    # Add initial liquidity
    tick_lower = -1000
    tick_upper = 1000
    liquidity_amount = Decimal('1000000')
    
    amount0, amount1 = pool.add_liquidity(
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        amount=liquidity_amount
    )
    
    print("Initial liquidity added:")
    print(f"Amount0: {amount0}")
    print(f"Amount1: {amount1}")
    print(f"Current price: {pool.get_current_price()}")
    print(f"Current reserves: {pool.get_reserves()}")
    
    # Execute some swaps
    print("\nExecuting swaps...")
    
    # Swap 1000 token0 for token1
    amount_in, amount_out, fee = pool.execute_swap(
        amount_in=Decimal('1000'),
        zero_for_one=True
    )
    print(f"\nSwapped {amount_in} token0 for {amount_out} token1")
    print(f"Fee: {fee}")
    print(f"New price: {pool.get_current_price()}")
    print(f"New reserves: {pool.get_reserves()}")
    
    # Swap 500 token1 for token0
    amount_in, amount_out, fee = pool.execute_swap(
        amount_in=Decimal('500'),
        zero_for_one=False
    )
    print(f"\nSwapped {amount_in} token1 for {amount_out} token0")
    print(f"Fee: {fee}")
    print(f"New price: {pool.get_current_price()}")
    print(f"New reserves: {pool.get_reserves()}")
    
    # Add more liquidity
    print("\nAdding more liquidity...")
    amount0, amount1 = pool.add_liquidity(
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        amount=liquidity_amount
    )
    print(f"Amount0: {amount0}")
    print(f"Amount1: {amount1}")
    print(f"Final price: {pool.get_current_price()}")
    print(f"Final reserves: {pool.get_reserves()}")

if __name__ == "__main__":
    main() 