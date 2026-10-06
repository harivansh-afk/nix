# File access authentication

Research checked against official documentation on 2026-10-06. This records a
proposed configuration, not a claim that the Cloudflare account is configured.

## Recommendation

Use **Cloudflare Access independent MFA**, allowing only **Security key** for
`files.harivan.sh`. Access now performs browser WebAuthn itself; Google or GitHub
can establish identity without being responsible for enforcing the key. This
avoids an additional authentication service. Cloudflare documents both per-app
security-key requirements and organization-wide AAGUID enrollment restrictions.
[Independent MFA][mfa] · [Enforcement][enforce]

Configure one Allow policy with the owner's exact verified email. Select only
the intended identity provider for the application. Enable independent MFA at
the organization level, then give this application custom MFA settings:

- Allowed authenticators: `security_key` only. The similarly named
  `ssh_fido2_key` and `piv_key` methods apply to infrastructure SSH, not this web
  application.
- MFA duration: `0m` / **Require every login**.
- Disable **Use identity provider MFA** (`amr_matching_enabled: false`), so an
  IdP claim cannot substitute for Access's key check.
- Check every matching policy: a policy can override the application's MFA
  settings, including disabling MFA.
- Start with a one-hour application session, with no longer policy override;
  verify actual expiry behavior in a browser. This is a usability/security
  recommendation, not a Cloudflare requirement.

Use an AAGUID allowlist for the actual primary and spare YubiKey models if the
requirement is specifically those hardware models. Cloudflare checks browser
WebAuthn AAGUID restrictions **at enrollment**. Existing enrollments therefore
need review; do not assume changing this allowlist revokes old browser keys.
Older U2F-only keys may omit AAGUID and fail enrollment. AAGUID identifies a
model, not a particular owner's physical key; registration binds the individual
credential. The documented feature should not be described as an independently
audited guarantee of attestation verification. [Independent MFA][mfa]

## Provider choices

| Choice | What it establishes | Limitation / work |
| --- | --- | --- |
| Email one-time PIN + Access independent MFA | Mailbox identity, then an Access-enrolled security key | Supported without an OAuth app: Access documents OTP as an IdP alternative and explicitly allows OTP for MFA enrollment. Restrict to the exact owner email and still require `security_key`; email PIN alone must never satisfy the application policy. [OTP integration][otp] · [Independent MFA][mfa] |
| Personal Google account + Access independent MFA | Google identity, then an Access-enrolled security key | Google Workspace is unnecessary. Create a Google OAuth web client and register the Cloudflare callback. Native Google is absent from Access's supported IdP-MFA-claim list; do not rely on it to prove a key was used. [Google integration][google] · [Enforcement][enforce] |
| GitHub + Access independent MFA | GitHub identity, then an Access-enrolled security key | Create a GitHub OAuth app; authorize read-only email/organization access. GitHub native integration also lacks documented IdP-MFA enforcement. GitHub's own security-key 2FA retains TOTP/SMS alternatives, so enabling a key there is not key-only enforcement. [GitHub integration][github] · [GitHub 2FA][github-2fa] · [Enforcement][enforce] |
| Self-hosted Authentik | Locally controlled identity, WebAuthn enrollment and required validation | Supports WebAuthn device-class validation and model restrictions at enrollment and validation. Set missing-device behavior to Deny after enrollment, not Skip, and require the validation stage in the login flow. Requires another service and recovery/upgrade operations. Browser “security key” hints alone are advisory. [Setup stage][auth-setup] · [Validation stage][auth-validate] |

Google Advanced Protection is useful account protection, but it permits both
security keys and passkeys and can reuse signed-in sessions. It is not evidence
that each visit to the files application used a physical YubiKey.
[Google Advanced Protection][google-advanced]

The generic `mfa` authentication-method claim means multiple factors were used;
it does not mean a physical key was used. Cloudflare supports IdP-based method
enforcement for Okta, Entra ID, generic OIDC and generic SAML. Native Google and
GitHub are not on that list. Independent MFA avoids needing to infer hardware
use from their claims. [Enforcement][enforce]

Email PIN is the simplest initial identity option. Before the first key is
enrolled, anyone controlling the allowed mailbox can enroll their own key; the
same window reopens if an administrator removes every enrolled authenticator.
After enrollment, adding or removing devices requires an existing MFA factor.
Enroll and inspect the primary and spare keys immediately, and protect the
mailbox and Cloudflare administration account. [Independent MFA][mfa]

Cloudflare advertises Access's Free plan with a 50-user limit. Neither the
Independent MFA documentation nor its launch announcement states an Enterprise
restriction, but the public pricing table does not explicitly itemize
Independent MFA. Free-plan entitlement therefore remains to be confirmed in
the actual account; these sources do not justify promising it or claiming it
requires Enterprise. [Access pricing][pricing] · [Launch announcement][launch]

## Sessions and origin enforcement

Successful Access login issues an application JWT, normally in
`CF_Authorization`. The application/session lifetime controls continued access.
MFA `0m` means a challenge on each **Access login**, not on every HTTP request;
MFA session duration does not invalidate an existing application session.
[Session management][sessions]

Explicitly enable HttpOnly and the binding cookie for this browser application;
use SameSite=Lax unless testing establishes a stricter setting works. The
binding cookie prevents replay of the authorization cookie alone, but does not
protect a compromised browser that can use both cookies. Cloudflare warns that
SameSite=Strict can cause redirect loops and that binding cookies conflict with
some products and non-browser clients. Test the editor/upload flow after these
settings change. [Cookies][cookies]

Validate Access at the tunnel as well as the edge. On the private hostname's
ingress rule, set:

```yaml
originRequest:
  access:
    required: true
    teamName: <actual-team-name>
    audTag:
      - <actual-files-application-AUD>
```

Cloudflared then validates the `Cf-Access-Jwt-Assertion` before proxying. If
validation is instead implemented in the application/proxy, verify signature,
issuer, audience and expiration against the team's rotating public keys; the
mere presence of the header is insufficient. Keep backend listeners on loopback
and audit alternate tunnel/hostname routes. Tunnel validation protects requests
through that ingress; it does not authenticate a local process connecting
directly to the backend. [Origin parameters][origin] · [JWT validation][jwt]

## Public sharing

Proposed boundary: `files.harivan.sh` is entirely behind Access;
`share.harivan.sh` accepts only signed public-file reads. The latter must reject
browsing, login, uploads, editing, listing shares and creating shares, including
when a valid private credential is supplied. Validate a share token in the
application before opening its file. A separate hostname by itself does not
create this boundary; it needs an explicit restricted server/proxy mode.

Do not implement a query-token-based Access bypass on the private hostname.
Cloudflare's Bypass action disables Access enforcement and Access request
logging. Keep public share URLs as their own deliberately limited bearer-token
surface, with expiry and revocation. Existing `files.harivan.sh` share links
need an explicit migration decision before enabling the full-host Access gate.
[Access policies][policies]

## Interactive steps and acceptance

1. Establish the Cloudflare Zero Trust organization/team domain and confirm the
   account exposes Independent MFA. OAuth client registration is needed if the
   chosen Google/GitHub integration is not already configured. Keep client
   secrets out of the Nix store. [Google][google] · [GitHub][github] · [MFA][mfa]
2. The owner signs in to the team's App Launcher and enrolls the primary and
   spare physical keys under **Account → MFA devices**. This requires the keys,
   browser interaction, and any authenticator PIN/touch; it cannot be completed
   by an unattended server deployment. Existing Google/GitHub key registrations
   do not enroll those keys with Cloudflare Access. [Enrollment][mfa]
3. Inspect enrolled devices before enforcement. The first device requires only
   IdP login; subsequent additions/removals require an existing MFA device.
   Administrators can reset authenticators, so protect the Cloudflare admin
   account and its recovery path with hardware MFA too. Access's documented
   lockout recovery is administrator removal and re-enrollment, not a promise
   of downloadable Access recovery codes. [Authenticator management][mfa]
4. Test from a fresh browser: allowed identity plus either registered key
   succeeds; wrong identity and no key fail. Confirm no OTP-only, alternate
   policy, service-token or hostname route bypasses the key gate. Test session
   expiry, uploads/editor operations and the spare key before ending the setup
   session. Confirm missing/invalid origin JWTs fail and public links expose
   only the signed file. These are proposed acceptance checks, not completed
   tests.

[mfa]: https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/
[otp]: https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/one-time-pin/
[pricing]: https://www.cloudflare.com/zero-trust/products/access/
[launch]: https://developers.cloudflare.com/changelog/post/2026-04-15-independent-mfa/
[enforce]: https://developers.cloudflare.com/cloudflare-one/access-controls/policies/mfa-requirements/
[google]: https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/google/
[github]: https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/github/
[github-2fa]: https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication
[google-advanced]: https://support.google.com/accounts/answer/7519408?hl=en
[auth-setup]: https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_webauthn/
[auth-validate]: https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate/
[sessions]: https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/
[cookies]: https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/
[origin]: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/origin-parameters/
[jwt]: https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/
[policies]: https://developers.cloudflare.com/cloudflare-one/access-controls/policies/
