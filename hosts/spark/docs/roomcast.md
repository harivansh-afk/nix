# Roomcast deployment and shared chat

## Ownership

The public Roomcast repository owns the resolver, media relay, Roku client, MCP
server, package and reusable NixOS module. This flake imports that module and pins
the source revision in flake.lock. hosts/spark/services/roomcast.nix owns the TV
identity, network addresses and Hermes integration. Updating Roomcast upstream
does not deploy it until this flake's pin changes and Spark switches.

Roomcast's tools accept content identifiers and playback commands, never a TV IP,
shell command or arbitrary media URL. The TV serial is deployment policy. An IP
reassigned to another TV fails the serial check before control commands are sent.
The serial check prevents accidental targeting; Roku ECP is not authenticated TLS
and a serial number is not a credential against a malicious LAN peer.

## Network prerequisite

The initial deployment uses observed addresses, not verified DHCP reservations:
Spark 10.41.1.145 and Roku 10.41.1.210. Do not describe them as stable. Spark's
live DHCP configuration on 2026-09-06 reported a /16 mask and a 104800-second lease.
10.41.1.x and 10.41.2.x therefore belong to Spark's same configured IP subnet;
wireless client isolation or network access controls may still limit traffic.

The addresses are editable NixOS options, not constants inside Roomcast. Both the
listener/firewall and advertised media URL depend on them. A changed Spark lease
can break the return path even when the TV remains reachable. A changed Roku lease
can break control and the source-restricted firewall rule.

Before relying on unattended operation, obtain DHCP reservations for both devices
from the network operator. Do not set arbitrary static addresses on their managed
network. If reservations are unavailable, address discovery and dynamic listener /
firewall handling require a separate implementation and acceptance test. Roku's
SSDP discovery is documented at https://developer.roku.com/dev/docs/external-control-api.
A four-second SSDP probe from Spark on 2026-09-06 received zero responses; this does
not distinguish host firewall filtering from network multicast filtering or a
silent device. Do not promise that discovery will cross isolation boundaries.

Required reachability is Spark -> Roku TCP 8060 and Roku -> Spark TCP 18795.
Discovery would additionally require functioning SSDP. A model cannot repair
network isolation by guessing another address. Request changes from the network
operator or place both devices on an approved private LAN if those paths are denied.

The observed playback test used a temporary Mac TCP forward to the Spark relay.
It proves playback and remux compatibility, not the permanent direct return path.
After deployment, verify a fresh play through Spark's listener and advancing Roku
position with the temporary forward removed. A DHCP renewal/reconnect test is
required before claiming address recovery works.

## Shared iMessage setup is separate work

Merging the Roomcast integration does not provision a secure roommate chat.
The pinned Hermes Photon adapter supplies chat type, chat ID and sender ID, but
this deployment configures the personal hermes-cli and knowledge_base toolsets
for Photon as a whole. The Photon adapter does not override toolsets by source.
A PHOTON_ALLOWED_USERS entry grants platform-wide access, including DMs; it is not
a TV-only role. Separate conversational sessions do not isolate tool permissions
or the personal process's files and credentials.

Implement a trusted routing boundary before inviting roommates to use the bot:

1. Keep Hari's personal DM route separate. Reject groups from the personal route,
   including group messages sent by Hari. Unknown chats and senders fail closed.
2. Authorize the exact roommate group ID AND each verified sender ID from Photon
   metadata. Do not derive identity from names or message text. Membership changes
   must not automatically grant a new person access.
3. Route accepted group messages into a separate service account/runtime with its
   own conversation state and only the Roomcast MCP tools. Exclude personal memory,
   KB, browser profiles, shell, files, scheduling, delegation and administrative
   commands. Tool filtering alone is insufficient if the process retains access.
4. Keep transport credentials and reply destinations in the trusted router. Return
   replies only to the originating authorized chat. The model cannot nominate a
   different recipient or modify policy. Deduplicate incoming message IDs and cap
   request rate and concurrent work.
5. Confirm the tool inventory and denial paths in integration tests: an unknown
   sender, the right sender in the wrong chat, a roommate DM, forged identity in
   text, administrative slash commands and a request for personal data. Verify
   ordinary playback, pause, stop and competing playback requests.

After that integration exists, the human onboarding steps are: register the
roommates' iMessage sender identifiers privately, create a group containing them
and the chosen bot identity, register the bridge's actual group ID, then test one
play request and an unauthorized request. A separate bot identity is the simplest
routing boundary; sharing the current identity needs the trusted split above and
must not attach two competing consumers to one Photon connection. No second
identity, group allowlist or router has been provisioned by this PR.

A wake phrase such as "Spark, play ..." can reduce accidental interruptions. It is
not authorization. Prompts guide behavior; runtime permissions enforce its scope.
