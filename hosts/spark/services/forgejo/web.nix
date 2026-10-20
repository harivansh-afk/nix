{
  forgejoDomain,
  forgejoPackage,
  lib,
  pierreForgejo,
  pkgs,
  ...
}:
let
  mkAuthMail = args: pkgs.replaceVars ./mail-auth.tmpl.in ({ domain = forgejoDomain; } // args);

  mails = {
    activate = mkAuthMail {
      title = "Welcome to ${forgejoDomain}";
      heading = "Welcome to ${forgejoDomain}";
      urlExpr = ''printf "%suser/activate?code=%s" AppUrl (QueryEscape .Code)'';
      buttonLabel = "Confirm your account";
      codeLivesVar = ".ActiveCodeLives";
    };
    reset_passwd = mkAuthMail {
      title = "Reset your password";
      heading = "Reset your password";
      urlExpr = ''printf "%suser/recover_account?code=%s" AppUrl (QueryEscape .Code)'';
      buttonLabel = "Reset password";
      codeLivesVar = ".ResetPwdCodeLives";
    };
    activate_email = mkAuthMail {
      title = "Confirm your new email";
      heading = "Confirm your new email";
      urlExpr = ''printf "%suser/activate_email?code=%s&email=%s" AppUrl (QueryEscape .Code) (QueryEscape .Email)'';
      buttonLabel = "Confirm email";
      codeLivesVar = ".ActiveCodeLives";
    };
  };
in
{
  public = pkgs.runCommand "harivan-forgejo-public" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    mkdir -p $out/assets/css $out/assets/img
    cp ${./assets}/css/* ${pierreForgejo.assets}/css/pierre-forgejo.css $out/assets/css/
    cp -R ${pierreForgejo.frontend}/js $out/assets/js

    cp ${./icon.svg} $out/assets/img/favicon.svg
    cp ${./icon.svg} $out/assets/img/logo.svg
    rsvg-convert -w 192 -h 192 ${./icon.svg} > $out/assets/img/favicon.png
    rsvg-convert -w 180 -h 180 ${./icon.svg} > $out/assets/img/apple-touch-icon.png
    rsvg-convert -w 512 -h 512 ${./icon.svg} > $out/assets/img/logo.png
  '';

  templates = pkgs.runCommand "harivan-forgejo-templates" { } ''
    cp -R ${./templates}/. $out/
    chmod -R u+w $out

    mkdir -p $out/repo/diff $out/mail/auth
    cp ${pierreForgejo.templates}/repo/diff/box.tmpl $out/repo/diff/box.tmpl
    ${lib.concatStrings (
      lib.mapAttrsToList (name: tmpl: "cp ${tmpl} $out/mail/auth/${name}.tmpl\n") mails
    )}

    cp ${forgejoPackage.data}/templates/repo/commit_header.tmpl $out/repo/commit_header.tmpl
    cp ${forgejoPackage.data}/templates/repo/shabox_badge.tmpl $out/repo/shabox_badge.tmpl
    chmod u+w $out/repo/commit_header.tmpl $out/repo/shabox_badge.tmpl

    substituteInPlace $out/repo/commit_header.tmpl \
      --replace-fail \
        '{{ctx.AvatarUtils.AvatarByEmail .Verification.SigningEmail "" 28 "tw-mr-2"}}' \
        '<img loading="lazy" alt="" class="ui avatar tw-align-middle tw-mr-2" src="{{AppSubUrl}}/assets/img/forgejo.svg" title="Forgejo" width="28" height="28"/>'
    substituteInPlace $out/repo/shabox_badge.tmpl \
      --replace-fail \
        '{{ctx.AvatarUtils.AvatarByEmail .verification.SigningEmail "" 28}}' \
        '<img loading="lazy" alt="" class="ui avatar tw-align-middle" src="{{AppSubUrl}}/assets/img/forgejo.svg" title="Forgejo" width="28" height="28"/>'

    version_for() {
      sha256sum "$1" | cut -c1-16
    }

    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __HARIVAN_FORGEJO_CSS_VERSION__ "$(version_for ${./assets}/css/harivan-forgejo.css)"
    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __PIERRE_FORGEJO_CSS_VERSION__ "$(version_for ${pierreForgejo.assets}/css/pierre-forgejo.css)"
    substituteInPlace $out/custom/footer.tmpl \
      --replace-fail __PIERRE_FORGEJO_JS_VERSION__ "$(version_for ${pierreForgejo.frontend}/js/pierre-forgejo.js)"
  '';
}
