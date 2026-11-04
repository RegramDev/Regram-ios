#!/usr/bin/env python3
"""Run the production notification-delivery decision with isolated Postbox/peer adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TelegramCore/Sources/State/AccountStateManager.swift').read_text()
production = source[source.index('public func rgShouldRemindGroupMember'):].replace('public func ', 'func ')
with tempfile.TemporaryDirectory(prefix='regram-member-alerts-') as directory:
    work = Path(directory)
    path = work / 'ProductionNotificationDelivery.swift'
    path.write_text('import Foundation\n' + production)
    simple = root / 'Regram/RGSimpleSettings'
    sources = [simple / f'Sources/{name}.swift' for name in ['MessageFilter', 'GroupMemberSelection', 'NotificationFilterPolicy', 'GroupMemberReminder']]
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors'] + [str(p) for p in sources] + [str(path), str(simple / 'Tests/GroupNotificationDeliveryTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
