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
Done!

### P2: make this something other hardcore betting nerds might use

- **Internals:**

    - show users their balances with other users
    - CSRF for XSS safety (maybe? or maybe CORS protects us)

### P3: make this something Less Wrongers might use
- **Features:**

    - get a better bot name (maybe even an email domain if easy?)
    - enhance "trust": "I don't want Alice to be able to owe me more than $1k"
    - enhance "trust": "I don't want to be able to owe everybody-combined more than $1k"
    - let the creator or challenger mark a particular trade as invalid

- **UI:**

    - add donation instructions

- **Explanations:**

    - tutorial video?

- **Internals:**

    - scale test
    - cache images?
    - consider letting people download a list of all their bets (Is this satisfied just Ctrl-S on an "All my markets" page?)

- **Advertisement:**

    - advertise to Caplan/Hanson/LessWrong/EAG/CFAR?

### P4: things I'll do once I quit my software engineering job to follow this dream
- consider making "Special Rules" show up not just as an H.text
- add "hide embeds" button for bettophobes (deceptively complicated! The user doesn't log in, so we have to store it in their cookie, but it should appear on some pages (all pages? Just Settings?))
- offer to shame users by emailing the participants if they greatly exceed the resolution deadline
- monetize via freemium or subscription?
- market privacy controls
- consider allowing "soft resolutions" so a market can resolve "80% yes"
- show users each other's calibratedness / score / bets
- add "Sign in with [identity provider]"
- do fancy stuff with dynamic images, displaying how much money's left in the pot
- let people subscribe to their mutuals' bets (RSS?)
