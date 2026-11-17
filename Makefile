.PHONY: test test-lean audit acceptance benchmark acceptance-benchmark

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

acceptance-benchmark:
	python3 tools/acceptance.py --lean --benchmark $(if $(ESTATE_AUDITOR),--audit "$(ESTATE_AUDITOR)")
