# MARK: Regram — the beta branch has one declared application identity.
def require_beta_bundle_id(bundle_id):
    if bundle_id != "com.regram.app":
        fail("This branch requires Bundle ID com.regram.app and App Group group.com.regram.app")
