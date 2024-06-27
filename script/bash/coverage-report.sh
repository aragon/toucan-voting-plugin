#!/bin/bash

### FUNCTIONS

# Function to add 'abstract' prefix
make_abstract() {
    local file_path="$1"
    local contract_name="$2"

    # Check if the string 'contract "$contract_name" is' exists
    if ! grep -q "contract "$contract_name" is" "$file_path"; then
        echo "Warning: 'contract "$contract_name" is' not found in the file."
        return 1
    fi

    # Check if the string 'abstract contract "$contract_name" is' already exists
    if grep -q "abstract contract "$contract_name" is" "$file_path"; then
        echo "Warning: 'abstract contract "$contract_name" is' already present."
        return 1
    fi

    # Replace 'contract "$contract_name" is' with 'abstract contract "$contract_name" is'
    sed -i "s/contract $contract_name is/abstract contract $contract_name is/" "$file_path"
    echo "Replaced 'contract "$contract_name" is' with 'abstract contract "$contract_name" is' in file $file_path"
}

# Function to remove 'abstract' prefix
remove_abstract() {
    local file_path="$1"
    local contract_name="$2"

    # Check if the string 'abstract contract "$contract_name" is' exists
    if ! grep -q "abstract contract "$contract_name" is" "$file_path"; then
        echo "Warning: 'abstract contract "$contract_name" is' not found in the file."
        return 1
    fi

    # Replace 'abstract contract "$contract_name" is' with 'contract "$contract_name" is'
    sed -i "s/abstract contract $contract_name is/contract $contract_name is/" "$file_path"
    echo "Replaced 'abstract contract "$contract_name" is' with 'contract "$contract_name" is' in file $file_path"
}

command_exists() {
    command -v "$1" &>/dev/null
}

### BEGIN SCRIPT

# layer zero coverage is not supported due to stack too deep
# copy the integration tests && lz code to a temp dir
# make the offending "endpoint" contracts abstract
# run forge coverage
# move the code back to the original directory and make the endpoint contracts non-abstract
# this also creates a coverage report, and removes unneccessary files

ROOT_DIR="src/layer-zero/LayerZero-v2"
PROTOCOL_DIR="protocol/contracts"
EndpointV2="$ROOT_DIR/$PROTOCOL_DIR/EndpointV2.sol"
EndpointV2Alt="$ROOT_DIR/$PROTOCOL_DIR/EndpointV2Alt.sol"
TMP_DIR="tmp"

# Check if lcov and genhtml are installed
if ! command_exists lcov || ! command_exists genhtml; then
    echo "Error: lcov or genhtml is not installed." >&2
    exit 1
fi

# Create integration directory if it doesn't exist
mkdir -p ./$TMP_DIR
mkdir -p ./$TMP_DIR/integration
mkdir -p ./$TMP_DIR/layer-zero-test

# Move files from ./test/integration to ./integration
mv ./test/integration/* ./$TMP_DIR/integration/
mv ./src/layer-zero/LayerZero-v2/oapp/test/* ./$TMP_DIR/layer-zero-test/

# Add 'abstract' prefix to the contracts - which prevents a stack too deep
make_abstract "$EndpointV2" "EndpointV2"
make_abstract "$EndpointV2Alt" "EndpointV2Alt"

# Run forge coverage and capture the exit status
# this ensures that the files get moved back even if the script fails
# Also prune the coverage report to remove files that are not part of the project
# The layer zero contracts are imported directly and the pragma has been changed
# we are not testing them directly
forge coverage --report lcov &&
    lcov --remove ./lcov.info -o ./lcov.info.pruned \
        'test/**/*.sol' 'script/**/*.sol' 'test/*.sol' \
        'script/*.sol' 'src/layer-zero/LayerZero-v2/**' &&
    genhtml lcov.info.pruned -o report --branch-coverage

status=$?

# Remove the 'abstract' prefix from the contracts
remove_abstract "$EndpointV2" "EndpointV2"
remove_abstract "$EndpointV2Alt" "EndpointV2Alt"

# Move files back to ./test/integration
mv ./$TMP_DIR/integration/* ./test/integration/
mv ./$TMP_DIR/layer-zero-test/* ./src/layer-zero/LayerZero-v2/oapp/test/

# Remove the temporary directory
rm -rf ./$TMP_DIR

# Exit with the status of forge coverage
exit $status
