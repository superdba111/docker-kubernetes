# Staff Platform Engineer: Security Review Exercise

Thanks for making it this far. This exercise looks like one ordinary day in
the role: a product team needs to ship something into a regulated environment
on a deadline, and you're the security reviewer.

> **Everything here is fictional.** "Foundry Analytics", account IDs, domains,
> people, and CVE IDs are made up. You don't need an AWS account, and you
> don't need to deploy anything.

## The situation

You're the Security Reviewer on the Platform team at Foundry Analytics.
Foundry runs a SaaS analytics product. Part of it runs in `govhigh`, an AWS
GovCloud environment aligned to FedRAMP High.

An engineer from the Data Products team opened a **pull request**
(`feature/data-export` → `main`) that adds a customer bulk-export feature.
A federal customer's contract milestone depends on it **this Friday**, and
leadership has already committed to the date. They asked you for review today
(Monday).

## What's in this repo

```
README.md                     <- you are here: the assignment
PULL_REQUEST.md               <- the PR description as the author wrote it
PLATFORM.md                   <- overview of Foundry's platform repo
ci-artifacts/
  export-service-scan.txt     <- CI's vulnerability scan of the new image
docs/ terraform/ helm/ services/ .github/ CODEOWNERS
                              <- Foundry's platform repo

Branches:
  main                 = current production state
  feature/data-export  = the PR
```

To see the change: open the pull request in this GitHub repo, or run
`git diff main...feature/data-export` locally.

Read `docs/` first. Those are the rules you're reviewing against.
`ingest-api` is the reference implementation that has already passed review.

## What we want back

Put these in a folder called `review/`:

1. **`review.md`: your PR review.** Write comments the way you'd actually
   post them on the PR: file/area, a label from
   `docs/security-review-policy.md` §2, what's wrong, why it matters here,
   and what you want instead. Order matters. Put what matters most first.
   Include things you looked at and decided are **fine**, and say why.

2. **`decision.md`: your call on Friday.** One page at most, written for the PR
   author, their manager, and our Platform Engineering Manager. Can this ship Friday?
   If not, is there anything that can? What happens next, who owns what, and
   what do you need from whom?

3. **`scan-triage.md`: triage of the CI scan.** One row per finding (grouping
   is fine): disposition (fix now / fix within SLA / false positive / accept
   with exception / not applicable) and a one-line reason. Then write **one**
   complete exception using `docs/templates/risk-acceptance.md` for the item
   you think most needs one.

4. **One fix, implemented.** Pick the fix you think matters most, or a small
   set of related fixes, and commit it on a branch `review/<your-name>` off
   `feature/data-export`, together with your `review/` folder. It should be a
   real, reviewable diff. Tell us in `review.md` why you picked that one.

5. **`ai-usage.md`: how you used AI tools (a few sentences).** Using AI is
   **allowed** and does not count against you. Tell us which tools you used,
   what for, and at least one place where you disagreed with or corrected
   what it gave you. If you didn't use any, say so.

## Time

**Spend no more than 4 hours.** There's more in this PR than anyone can fix in
4 hours. Deciding what matters most is part of the exercise. If you run out of
time, add a short "what I'd do next" list and stop.

## Returning it

Push your `review/<your-name>` branch to this repo, or zip the whole repo
(including `.git`), by the deadline in your invitation email.

## What happens next

We'll schedule a **75-minute follow-up call**. You'll walk us through your
review, we'll ask "why" a lot, we'll change some of the constraints, and we'll
do a short live troubleshooting exercise together. Expect to explain your
reasoning in your own words: how you found things, what you checked, and
where you've seen similar problems before.

Questions about the exercise itself? Email us anytime. We won't give hints on
the content, but we're happy to clear up logistics.
