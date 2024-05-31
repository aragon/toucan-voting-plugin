#!/bin/bash

# layer zero coverage is not supported due to stack too deep
# copy the integration tests to a temporary directory
# run forge coverage
# move the integration tests back to the original directory

TMP_DIR="tmp"

# Create integration directory if it doesn't exist
mkdir -p ./$TMP_DIR

# Move files from ./test/integration to ./integration
mv ./test/integration/* ./$TMP_DIR/

# Run forge coverage and capture the exit status
# this ensures that the files get moved back even if the script fails
forge coverage
status=$?

# Move files back to ./test/integration
mv ./$TMP_DIR/* ./test/integration/

# Remove the temporary integration directory
rmdir ./$TMP_DIR

# Exit with the status of forge coverage
exit $status
