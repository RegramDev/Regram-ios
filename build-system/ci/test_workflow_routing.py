"""Keep TestFlight signing on beta and the default-branch entry point inert."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DistributionWorkflowChecks(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/testflight.yml').read_text()
        self.beta = (ROOT / 'build-system/bazel-utils/beta_identity.bzl').exists()

    def test_testflight_is_manual_only(self):
        triggers = self.workflow.split('on:', 1)[1].split('permissions:', 1)[0]
        self.assertIn('workflow_dispatch:', triggers)
        self.assertNotRegex(triggers, r'(?m)^  (push|pull_request|schedule|workflow_run):')

    def test_dispatch_inputs_remain_compatible_between_branches(self):
        self.assertIn('options: [build, publish, distribute]', self.workflow)
        self.assertIn('build_number:', self.workflow)

    def test_signing_execution_is_confined_to_beta(self):
        if self.beta:
            self.assertRegex(self.workflow, r"(?m)^    if: github.ref == 'refs/heads/regram-beta'$")
            self.assertIn('REGRAM_BUILD_CONFIGURATION: ${{ secrets.REGRAM_BETA_BUILD_CONFIGURATION }}', self.workflow)
            self.assertIn('run: bash build-system/ci/testflight-build.sh', self.workflow)
            self.assertIn('inputs.mode == \'publish\'', self.workflow)
        else:
            self.assertIn('Select regram-beta', self.workflow)
            self.assertNotIn('secrets.', self.workflow)
            self.assertNotRegex(self.workflow, r'fastlane|codesign|actions/checkout|testflight\.py')
            self.assertIn('exit 1', self.workflow)

    def test_private_tooling_is_present_only_on_beta(self):
        for name in ['testflight.py', 'testflight-build.sh', 'private-command.py', 'TESTFLIGHT.md']:
            self.assertEqual((ROOT / 'build-system/ci' / name).exists(), self.beta, name)

    def test_reference_build_keeps_its_branch_configuration(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        expected = 'REGRAM_BETA_BUILD_CONFIGURATION' if self.beta else 'REGRAM_BUILD_CONFIGURATION'
        self.assertIn('secrets.' + expected, workflow)

    def test_github_release_stays_manual_and_master_only(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn("github.ref == 'refs/heads/master'", workflow)
        self.assertIn('confirm_publish', workflow)


if __name__ == '__main__':
    unittest.main()
