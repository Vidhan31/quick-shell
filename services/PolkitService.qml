pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Polkit

Item {
  id: root

  property bool enabledService: false

  readonly property PolkitAgent agent: agentLoader.item as PolkitAgent
  readonly property bool isRegistered: root.agent?.isRegistered ?? false
  readonly property bool isActive: root.agent?.isActive ?? false
  readonly property AuthFlow activeFlow: root.agent?.flow ?? null

  readonly property string message: root.activeFlow?.message ?? ""
  readonly property string actionId: root.activeFlow?.actionId ?? ""
  readonly property string iconName: root.activeFlow?.iconName ?? ""
  readonly property string prompt: root.activeFlow?.inputPrompt ?? "Password:"
  readonly property bool isResponseRequired: root.activeFlow?.isResponseRequired ?? false
  readonly property bool responseVisible: root.activeFlow?.responseVisible ?? false
  readonly property string supplementaryMessage: root.activeFlow?.supplementaryMessage ?? ""
  readonly property bool supplementaryIsError: root.activeFlow?.supplementaryIsError ?? false
  readonly property bool failed: root.activeFlow?.failed ?? false
  readonly property var identities: root.activeFlow?.identities ?? []
  property var selectedIdentity: root.activeFlow?.selectedIdentity ?? null

  signal requestStarted()
  signal requestCompleted(bool success)

  function submit(response: string): void {
    if (root.activeFlow) {
      root.activeFlow.submit(response);
    }
  }

  function cancel(): void {
    if (root.activeFlow) {
      root.activeFlow.cancelAuthenticationRequest();
    }
  }

  Loader {
    id: agentLoader
    active: root.enabledService

    sourceComponent: Component {
      PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: root.requestStarted()
      }
    }
  }

  Connections {
    target: root.activeFlow
    function onAuthenticationSucceeded(): void {
      root.requestCompleted(true);
    }
    function onAuthenticationRequestCancelled(): void {
      root.requestCompleted(false);
    }
  }
}
