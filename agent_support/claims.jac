"""Conservative phrase checks that preserve explicit evidence disclaimers."""
import re;

def asserts_terms(text: str, terms: list[str]) -> bool {
    for clause in re.split(r"[.;!?]|\b(?:but|however|yet)\b", text.lower()) {
        for term in terms {
            word = re.escape(term);
            remaining = re.sub(
                r"\b(?:not|never)(?: (?:known|confirmed|necessarily)(?: to be)?)?\s+" + word + r"\b",
                "",
                clause
            );
            subject = r"(?:[a-z_]+(?: [a-z_]+){0,2})";
            negated = r"\bno(?: direct)? evidence (?:that )?(?:" + subject + r" (?:is|are|was|were|has been|have been) )?" + word + r"\b";
            remaining = re.sub(negated, "", remaining);
            if re.search(r"\b" + word + r"\b", remaining) {
                return True;
            }
        }
    }
    return False;
}

def asserts_clean_scan(text: str) -> bool {
    for clause in re.split(
        r"[.;!?]|\b(?:but|however|yet)\b", text.lower().replace("-", " ")
    ) {
        remaining = re.sub(
            r"\b(?:not|never)(?: an?| the)? (?:all clear|verified clean)\b", "", clause
        );
        remaining = re.sub(
            r"\b(?:cannot|can't) (?:claim|establish|provide|verify)(?: an?)? (?:all clear|verified clean)\b",
            "",
            remaining
        );
        if `any(
            phrase in remaining
            for phrase in ["all clear", "no vulnerabilities", "verified clean"]
        ) {
            return True;
        }
    }
    return False;
}
