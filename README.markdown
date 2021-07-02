[Biatob](https://biatob.com) (Betting Is A Tax On Bullshit) is a site that enables people to make predictions, and make real-money bets against their friends. It might become popular, but probably not.[![(bet $200 @ 10-50%)](https://biatob.com/p/2592105452080787199/embed-darkgreen-14pt.png)](https://biatob.com/p/2592105452080787199) (Fortunately, it doesn't rely on network effects, so isolated people can use it here and there even if it doesn't see widespread adoption.)

**Target audiences:** people who want to get better at operationalizing their beliefs; people who want to publish bets in order to signal confidence and trustworthiness; people who think they have better world-models than their friends, and want to make money off that.

**Biatob's "market differentiator"** or whatever, vs other prediction-market-type things, is that it doesn't handle any actual money, instead relying on an honor system: you can only make bets against people you trust to pay up. This greatly reduces the number of potential counterparties for your bets, but also simplifies things greatly and removes the need to trust the site with your money.

How to develop
--------------

This project uses the `doit` build system: https://pydoit.org/tutorial_1.html

- `doit devsetup` tells you how to set up your environment.
- `doit` builds and tests everything.
- `doit auto` builds and tests everything whenever a relevant file changes.
- `doit nfsdeploy` deploys the current state (checked-in or not) to the NearlyFreeSpeech host (though you have to kick the server daemon yourself).
- `doit list` lists all the targets.


Dreamed-of enhancements
-----------------------

...that I don't care about enough to turn into GitHub issues:

- tutorial video
- scale test
- cache images
- consider letting people download a list of all their bets (Is this satisfied just Ctrl-S on an "All my markets" page?)
- advertise (to Caplan/Hanson/LessWrong/EAG/CFAR?)
- consider making "Special Rules" show up not just as an H.text
- add "hide embeds" button for bettophobes (deceptively complicated! The user doesn't log in, so we have to store it in their cookie, but it should appear on some pages (all pages? Just Settings?))
- offer to shame users by emailing the participants if they greatly exceed the resolution deadline
- monetize via freemium or subscription?
- market privacy controls
- consider allowing "soft resolutions" so a market can resolve "80% yes"
- show users each other's calibratedness / score / bets
- add "Sign in with [identity provider]"
- let people subscribe to their mutuals' bets (RSS?)
