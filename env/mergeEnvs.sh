#!/bin/bash

# Merge all env files into a single file
# @dev This is needed to execute the foundry tests directly ... Makefile would run nevertheless
cat .env.foundry .env.local .env.public .env.tokens .env.uniswap.public .env.hook > ../contracts/uniswap-v4-hook/.env.merged.local
