import itertools
import pandas as pd

# Constants
SQRT_RATIO_1_1 = 1.0  # Normal pool rate (1:1)
SQRT_RATIO_1_2 = 0.5  # Damped pool rate (1:2)
SQRT_RATIO_2_1 = 2.0  # Damped pool rate (2:1)
POOL_FEE = 3000 / 1_000_000  # 0.3%

# Define the four dimensions of the simulation
zeroForOne_options = [True, False]  # Swap direction
normalPoolHigher_options = [True, False]  # Normal rate above/below damped rate
dampedPoolOptions = [
    (False, None),  # Damping disabled
    (True, True),  # Damped Pool enabled, zeroForOne=True
    (True, False),  # Damped Pool enabled, zeroForOne=False
]

# Helper function to calculate swap amounts
def compute_swap(amountSpecified, normal_rate, damped_rate, zeroForOne):
    """
    Simulates a swap at both the normal rate and the damped rate.
    amountSpecified > 0 → exactInput, amountSpecified < 0 → exactOutput.
    """
    exactInput = amountSpecified >= 0  # Convention: sign determines exactInput/exactOutput

    if exactInput:
        amountIn = amountSpecified
        amountIn_damped = amountIn  # Same input amount for both cases
        amountOut = amountIn * (1 - POOL_FEE) / normal_rate
        amountOut_damped = amountIn * (1 - POOL_FEE) / damped_rate
    else:
        amountOut = -amountSpecified  # Convert negative to positive
        amountOut_damped = amountOut  # Same output amount for both cases
        amountIn = amountOut * normal_rate / (1 - POOL_FEE)
        amountIn_damped = amountOut * damped_rate / (1 - POOL_FEE)

    # Assign token directions (Normal Swap)
    token0In = amountIn if zeroForOne else 0
    token0Out = amountOut if not zeroForOne else 0
    token1In = amountIn if not zeroForOne else 0
    token1Out = amountOut if zeroForOne else 0

    # Assign token directions (Damped Swap)
    token0In_damped = amountIn_damped if zeroForOne else 0
    token0Out_damped = amountOut_damped if not zeroForOne else 0
    token1In_damped = amountIn_damped if not zeroForOne else 0
    token1Out_damped = amountOut_damped if zeroForOne else 0

    return {
        "token0In": token0In, "token0Out": token0Out, "token1In": token1In, "token1Out": token1Out,
        "token0In_damped": token0In_damped, "token0Out_damped": token0Out_damped,
        "token1In_damped": token1In_damped, "token1Out_damped": token1Out_damped
    }

if __name__ == "__main__":

    # Iterate over all possible cases
    results = []
    amountSpecified_values = [1, -1]  # 1 ETH for exactInput, -1 ETH for exactOutput

    for zeroForOne, normalPoolHigher, (dampedEnabled, dampedZeroForOne), amountSpecified in itertools.product(
        zeroForOne_options, normalPoolHigher_options, dampedPoolOptions, amountSpecified_values
    ):
        # Determine normal and damped pool rates
        normal_rate = SQRT_RATIO_1_1
        damped_rate = SQRT_RATIO_1_2 if normalPoolHigher else SQRT_RATIO_2_1

        # Compute normal and damped swap outcomes
        swapResults = compute_swap(amountSpecified, normal_rate, damped_rate, zeroForOne)

        # Determine if damping applies (choosing the worse rate for the swapper)
        if dampedEnabled:
            chosen_rate = damped_rate if dampedZeroForOne == zeroForOne else normal_rate
            swapResults_damped = compute_swap(amountSpecified, chosen_rate, damped_rate, zeroForOne)
        else:
            swapResults_damped = swapResults

        # Hook extraction: Can only extract if damping results in a surplus
        hookExtract = 0
        if dampedEnabled and swapResults_damped != swapResults:
            if zeroForOne:
                hookExtract = abs(swapResults_damped["token0Out"] - swapResults["token0Out"])
            else:
                hookExtract = abs(swapResults_damped["token1Out"] - swapResults["token1Out"])

        # Compute BalanceDelta before the hook reallocates
        balanceDelta_amount0 = swapResults["token0In"] - swapResults["token0Out"]
        balanceDelta_amount1 = swapResults["token1In"] - swapResults["token1Out"]

        # Hook settlement logic (beforeSwap for exactInput, afterSwap for exactOutput)
        exactInput = amountSpecified >= 0
        hookTake = hookExtract if exactInput else 0
        hookSettle = hookExtract if not exactInput else 0

        # Store results
        results.append({
            "zeroForOne": zeroForOne,
            "exactInput": exactInput,
            "normalPoolHigher": normalPoolHigher,
            "dampedEnabled": dampedEnabled,
            "dampedZeroForOne": dampedZeroForOne,
            "amountSpecified": amountSpecified,
            "token0In": swapResults["token0In"],
            "token0Out": swapResults["token0Out"],
            "token1In": swapResults["token1In"],
            "token1Out": swapResults["token1Out"],
            "token0In_damped": swapResults_damped["token0In"],
            "token0Out_damped": swapResults_damped["token0Out"],
            "token1In_damped": swapResults_damped["token1In"],
            "token1Out_damped": swapResults_damped["token1Out"],
            "hookExtract": hookExtract,
            "balanceDelta_amount0": balanceDelta_amount0,
            "balanceDelta_amount1": balanceDelta_amount1,
            "hookTake": hookTake,
            "hookSettle": hookSettle,
        })

    # Convert results to DataFrame for readability
    df = pd.DataFrame(results)

    # Format the numeric columns to 4 decimal places
    for col in ['token0In', 'token0Out', 'token1In', 'token1Out', 
                'token0In_damped', 'token0Out_damped', 'token1In_damped', 'token1Out_damped',
                'hookExtract', 'balanceDelta_amount0', 'balanceDelta_amount1']:
        df[col] = df[col].round(4)

    # Set display options for better readability
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_rows', None)
    pd.set_option('display.float_format', lambda x: '%.4f' % x)

    # Add separators between groups
    print("\n=== SWAP SIMULATION RESULTS ===\n")
    
    # Group by zeroForOne and exactInput for better readability
    for (zero_for_one, exact_input), group in df.groupby(['zeroForOne', 'exactInput']):
        print(f"\nSwap Direction: {'Zero→One' if zero_for_one else 'One→Zero'}, "
              f"Type: {'ExactInput' if exact_input else 'ExactOutput'}")
        print("-" * 100)
        print(group.to_string(index=False))
        print("-" * 100)
