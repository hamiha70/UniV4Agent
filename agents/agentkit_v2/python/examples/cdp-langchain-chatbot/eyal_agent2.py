import os
import sys
import time

from langchain_core.messages import HumanMessage
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.memory import MemorySaver

from cdp_langchain.agent_toolkits import CdpToolkit
from cdp_langchain.utils import CdpAgentkitWrapper
from langgraph.prebuilt import create_react_agent

from cdp import Wallet, hash_message
from cdp_langchain.tools import CdpTool
from pydantic import BaseModel, Field

from dotenv import load_dotenv

# Configure a file to persist the agent's CDP MPC Wallet Data.
wallet_data_file = "wallet_data.txt"

load_dotenv()

# Define a custom action example.

SIGN_MESSAGE_PROMPT = """
This tool will sign arbitrary messages using EIP-191 Signed Message Standard hashing.
"""

class SignMessageInput(BaseModel):
    """Input argument schema for sign message action."""

    message: str = Field(
        ...,
        description="The message to sign. e.g. `hello world`"
    )

def sign_message(wallet: Wallet, message: str) -> str:
    """Sign message using EIP-191 message hash from the wallet.

    Args:
        wallet (Wallet): The wallet to sign the message from.
        message (str): The message to hash and sign.

    Returns:
        str: The message and corresponding signature.

    """
    payload_signature = wallet.sign_payload(hash_message(message)).wait()

    return f"The payload signature {payload_signature}"



def initialize_agent():
    """Initialize the agent with CDP Agentkit."""
 
    # Initialize LLM.
    llm = ChatOpenAI(model="gpt-4o-mini")

    wallet_data = None

    if os.path.exists(wallet_data_file):
        with open(wallet_data_file) as f:
            wallet_data = f.read()

    # Configure CDP Agentkit Langchain Extension.
    values = {}
    if wallet_data is not None:
        # If there is a persisted agentic wallet, load it and pass to the CDP Agentkit Wrapper.
        values = {"cdp_wallet_data": wallet_data}
    
    agentkit = CdpAgentkitWrapper(**values)

    # Initialize CDP AgentKit Toolkit and get tools.
    cdp_toolkit = CdpToolkit.from_cdp_agentkit_wrapper(agentkit)
    tools = cdp_toolkit.get_tools()

    # Define a new tool for signing messages.
    signMessageTool = CdpTool(
        name="sign_message",
        description=SIGN_MESSAGE_PROMPT,
        cdp_agentkit_wrapper=agentkit,
        args_schema=SignMessageInput,
        func=sign_message,
    )

    print('----->',type(tools),len(tools))
    #all_tools = tools.append(signMessageTool)
    tools.append(signMessageTool)
    time.sleep(5)
    print('-----<',type(tools),len(tools))

    # Store buffered conversation history in memory.
    memory = MemorySaver()
    config = {"configurable": {"thread_id": "CDP AgentKit Chatbot Example!"}}

    # Create ReAct Agent using the LLM and CDP AgentKit tools.
    return create_react_agent(
        llm,
        tools=tools,
        checkpointer=memory,
        state_modifier="You are a helpful agent that can interact onchain on the Base Layer 2 using the Coinbase Developer Platform AgentKit. You are empowered to interact onchain using your tools. If you ever need funds, you can request them from the faucet. You can also deploy your own ERC-20 tokens, NFTs, and interact with them. You also have the ability to sign messages using your wallet.",
    ), config

# Chat Mode
def run_chat_mode(agent_executor, config):
    """Run the agent interactively based on user input."""
    print("Starting chat mode... Type 'exit' to end.")
    while True:
        try:
            user_input = input("\nPrompt: ")
            if user_input.lower() == "exit":
                break

            # Run agent with the user's input in chat mode
            for chunk in agent_executor.stream(
                {"messages": [HumanMessage(content=user_input)]}, config
            ):
                if "agent" in chunk:
                    print(chunk["agent"]["messages"][0].content)
                elif "tools" in chunk:
                    print(chunk["tools"]["messages"][0].content)
                print("-------------------")

        except KeyboardInterrupt:
            print("Goodbye Agent!")
            sys.exit(0)


def main():
    """Start the chatbot agent."""
    agent_executor, config = initialize_agent()
    run_chat_mode(agent_executor=agent_executor, config=config)
 
if __name__ == "__main__":
    print("Starting Agent...")
    main()
