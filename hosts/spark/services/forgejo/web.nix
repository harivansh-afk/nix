{
  forgejoPackage,
  pierreForgejo,
  pkgs,
  ...
}:
pkgs.runCommand "harivan-forgejo-web-templates" { } ''
  cp -R ${./templates}/. $out/
  chmod -R u+w $out

  mkdir -p $out/repo
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
''
