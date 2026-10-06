# Evaluation material

This directory preserves historical Rasc reliability work, corpora, adjudication
and milestone reports. Start with [current product](../docs/CURRENT-PRODUCT.md), not
an old experiment, to understand today's implementation.

Checked-in corpora and test fixtures are evaluation inputs. Generated reports
refer to specific code, prompts, model/environment and dates; they are not claims
about a current model or a newly packaged app. Scripts may require local Apple
Intelligence and can generate output under ignored report directories.

Add only synthetic or explicitly cleared inputs. Never copy a user's database,
private thoughts, clipboard, credentials or diagnostics containing content.
Preserve input provenance when adding a case. Before making the repository public,
the maintainer must confirm historical inputs/adjudication are cleared for public
use; a pattern-based credential scan cannot establish that consent or provenance.

A fresh checkout must run domain tests without generated local reports. Historical
schema compatibility tests use self-contained synthetic data rather than requiring
an ignored report from a previous machine.
