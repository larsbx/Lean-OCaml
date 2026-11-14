.PHONY: test test-lean audit acceptance

test:
	sh conformance/run.sh

test-lean:
	sh conformance/run.sh --lean

audit:
	sh tools/estate-audit.sh $(if $(ESTATE_AUDITOR),"$(ESTATE_AUDITOR)")

acceptance:
	python3 tools/acceptance.py --lean $(if $(ESTATE_AUDITOR),--audit "$(ESTATE_AUDITOR)")
