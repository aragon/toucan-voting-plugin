# Note on integration tests

Layer Zero TestHelper is currently used to fully mock the LzEndpoint. However, this cannot be used in coverage reports due to some stack-too-deep errors. The team have not provided any solution so far so this folder should not be included in coverage reports. Check the Makefile for a solution (move integration tests to a tmp folder, run coverage, then move back).