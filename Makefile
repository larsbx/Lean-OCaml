.PHONY: test test-lean audit acceptance benchmark benchmark-lean acceptance-benchmark test-goose benchmark-goose

test:
	sh conformance/run.sh

test-lean:
	sh conformance/run.sh --lean

audit:
	sh tools/estate-audit.sh $(if $(ESTATE_AUDITOR),"$(ESTATE_AUDITOR)")

acceptance:
	python3 tools/acceptance.py --lean $(if $(ESTATE_AUDITOR),--audit "$(ESTATE_AUDITOR)")

benchmark:
	sh tools/benchmark.sh $(BENCHMARK_ARGS)

benchmark-lean:
	python3 tools/compare_lean.py $(COMPARE_LEAN_ARGS)

test-goose:
	python3 tools/test_goose.py $(GOOSE_TEST_ARGS)

benchmark-goose:
	python3 tools/compare_goose.py $(GOOSE_BENCHMARK_ARGS)

acceptance-benchmark:
	python3 tools/acceptance.py --lean --benchmark $(if $(ESTATE_AUDITOR),--audit "$(ESTATE_AUDITOR)")
