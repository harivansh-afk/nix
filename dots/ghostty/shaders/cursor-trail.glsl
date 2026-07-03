const float trailSeconds = 0.16;
const float trailAlpha = 0.55;
const float trailWidth = 0.95;
const float trailSoftness = 2.0;
const float maxJumpCells = 80.0;

float rectSdf(vec2 point, vec2 center, vec2 halfSize) {
    vec2 delta = abs(point - center) - halfSize;
    return length(max(delta, 0.0)) + min(max(delta.x, delta.y), 0.0);
}

float segmentDistance(vec2 point, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float denom = dot(ab, ab);

    if (denom < 0.0001) {
        return length(point - b);
    }

    float t = clamp(dot(point - a, ab) / denom, 0.0, 1.0);
    return length(point - (a + ab * t));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 base = texture(iChannel0, fragCoord / iResolution.xy);

    vec2 currentSize = iCurrentCursor.zw;
    vec2 previousSize = iPreviousCursor.zw;
    vec2 currentCenter = iCurrentCursor.xy + currentSize * 0.5;
    vec2 previousCenter = iPreviousCursor.xy + previousSize * 0.5;

    float age = iTime - iTimeCursorChange;
    float moveDistance = length(currentCenter - previousCenter);
    float maxDistance = max(currentSize.y, 1.0) * maxJumpCells;

    if (age <= trailSeconds && moveDistance > 0.5 && moveDistance < maxDistance) {
        float progress = clamp(age / trailSeconds, 0.0, 1.0);
        float fade = 1.0 - smoothstep(0.0, 1.0, progress);

        float halfThickness = max(currentSize.x, currentSize.y) * 0.5 * trailWidth;
        float distanceToTrail = segmentDistance(fragCoord, previousCenter, currentCenter);
        float trailMask = 1.0 - smoothstep(0.0, trailSoftness, distanceToTrail - halfThickness);

        float cursorMask = 1.0 - smoothstep(0.0, trailSoftness, rectSdf(fragCoord, currentCenter, currentSize * 0.5));
        float alpha = trailMask * fade * trailAlpha * (1.0 - cursorMask);

        base = mix(base, vec4(iCurrentCursorColor.rgb, 1.0), alpha);
    }

    fragColor = base;
}
