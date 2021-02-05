This is a harebrained idea for a project to glorify betting. It provides a mechanism for writers to include little tags in their writing that indicate a willingness to bet on their claims.

This project does not touch real money: financial stuff is really hard; appropriate security is really hard; and it would probably be illegal. So, this project assumes an honor system. People will use it to make bets _with their friends,_ or people they trust, at least.

See [./mockup/user-stories.markdown](./mockup/user-stories.markdown) for descriptions of who uses this and how.

Development
-----------

This project uses the `doit` build system: https://pydoit.org/tutorial_1.html

`doit list` lists all the targets.

`doit proto` builds the `proto` target.

Extrapolate.


TODO
--------------
- P2 [pre-beta]: write copy explaining how to operationalize a bet well (or find somebody else's explanation)
- P2 [pre-beta]: figure out how to make ViewMarketPage less gnarly -- maybe just have totally separate functions for creator/challenger(/rando)?
- P2 [pre-beta]: link from more places to other places
- P2 [pre-beta]: add an actual home page
- P2 [pre-beta]: show users their balances with other users
- P2 [pre-beta]: link auth widget to your user page
- P2 [pre-beta]: consider a semi-formalized system for naming an arbiter
- P2 [pre-beta]: figure out how users can undo accidental bets
- P2 [pre-beta]: add "Sign in with [identity provider]"
- P2 [pre-beta]: make "bet"/"wager"/"market"/"stake"/"bettor"/"challenger" terminology consistent
- P2 [pre-beta]: _consider_ showing users each other's calibratedness / score / bets
- P3 [nice-to-have]: market privacy controls
- P3 [nice-to-have]: monetize via freemium or subscription?
- P3 [nice-to-have]: consider allowing "soft resolutions" so a market can resolve "80% yes"
- P3 [nice-to-have]: consider letting people download a list of all their bets
- P3 [nice-to-have]: advertise to Caplan/Hanson/LessWrong/EAG/CFAR?
- P4 [nice-to-have]: let people subscribe to their mutuals' bets (RSS?)
