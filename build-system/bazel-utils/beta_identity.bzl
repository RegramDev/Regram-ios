# MARK: Regram — the beta app and all extensions use the registered TestFlight identity.
def require_beta_bundle_id(bundle_id):
    if bundle_id != "dev.regram.ios":
        fail("This branch requires Bundle ID dev.regram.ios")
