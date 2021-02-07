This is a harebrained idea for a project to glorify betting. It provides a mechanism for writers to include little tags in their writing that indicate a willingness to bet on their claims.

This project does not touch real money: financial stuff is really hard; appropriate security is really hard; and it would probably be illegal. So, this project assumes an honor system. People will use it to make bets _with their friends,_ or people they trust, at least.

See [./mockup/user-stories.markdown](./mockup/user-stories.markdown) for descriptions of who uses this and how.

Development
-----------

This project uses the `doit` build system: https://pydoit.org/tutorial_1.html

- `doit devsetup` tells you how to set up your environment.
- `doit` builds and tests everything.
- `doit nfsdeploy` deploys the current state (checked-in or not) to the NearlyFreeSpeech host (though you have to kick the server daemon yourself).
- `doit list` lists all the targets.


TODO
--------------

### P1: make this something _I_ want to use
- offer to email users about resolved bets
- add an "all my markets" page
- add a navbar (auth / Home / New Market / My Markets / Settings)

### P2: make this something other hardcore betting nerds might use
- consider a better model of user identity -- UserUserView is gross
- add an actual home page
- finish the tutorial, integrate it into ViewMarketPage and the home page
- make the betting mechanism "more intuitive"
- write copy explaining how to operationalize a bet well (or find somebody else's explanation)
- display remaining stake even to people who can't bet
- add "Sign in with [identity provider]"
- make "bet"/"wager"/"market"/"stake"/"bettor"/"challenger" terminology consistent

### P3: make this something Less Wrongers might use
- add more fields to CreateMarketRequest:
    - "bettors are forbidden from trying to affect the outcome? [y/n]"
    - "if the result is disputed, who will arbitrate?"
    - "when will this market definitely be resolvable?"
- show users their balances with other users
- figure out how users can undo accidental bets
- scale test
- add "hide embeds" button for bettophobes (deceptively complicated! The user doesn't log in, so we have to store it in their cookie, but it should appear on some pages (all pages? Just Settings?))
- let people subscribe to their mutuals' bets (RSS?)
- consider letting people download a list of all their bets (Is this satisfied just Ctrl-S on an "All my markets" page?)
- advertise to Caplan/Hanson/LessWrong/EAG/CFAR?

### P4: things I'll do once I quit my software engineering job to follow this dream
- monetize via freemium or subscription?
- market privacy controls
- consider allowing "soft resolutions" so a market can resolve "80% yes"
- show users each other's calibratedness / score / bets
