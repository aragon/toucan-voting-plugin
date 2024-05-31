allow-scripts: 
	chmod +x script/bash/*.sh

coverage:
	./script/bash/coverage.sh

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage-report:
	./script/bash/coverage-report.sh