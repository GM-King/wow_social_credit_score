# Social Credit System

[Download 2.11.0](https://gm-king.github.io/wow_social_credit_score/downloads/SocialCreditSystem-2.11.0.zip) · [Installation and player guide](https://gm-king.github.io/wow_social_credit_score/)

Characters at any level can view and review known same-faction profiles. A character's 0-1000 Social Credit Score unlocks at level 60 after reviews from five distinct authors. Reviews received while leveling count automatically. Use the close button or Escape to close the profile in combat.

The composite uses 75% review rating and 25% instance combat. Reviews compare same-faction characters of the same class. Combat benchmarks also match the active talent tree, tank or non-tank role, and instance size. Each metric maps the local population's minimum, mean and maximum to 0, 500 and 1000. SCS uses the better of the DPS and HPS results in each qualifying bracket and averages those brackets. A bracket needs three verified clears for the player and five qualifying characters for a benchmark. Scores with insufficient combat data use a provisional combat value of 500.

Version 2.7 starts tracking talent trees and roles for new combat samples. The profile shows the active tree and uses the last confirmed role on that tree when the current role is unavailable. Hover over a bracket for lifetime DPS and HPS, including older runs and fights with no readable tree or confirmed role.

**Explicit Words** counts case-insensitive whole-word matches from the English list in `Stats.lua`, including the listed inflections. It covers the character's own readable local, group, guild and public chat, excluding whispers. The addon stores and syncs only the count and start date. The counter carries no score weight.

For World of Warcraft Forever, interface 16001. The addon is installed when this folder sits directly under the client's `Interface/AddOns` folder.

Click the black stamp on the minimap to open **Recent** and **Reviewed**. Recent keeps your character's last 100 distinct party, raid, and whisper contacts. Reviewed lists your active reviews. Click a row to open its profile, and use **Back to player history** to return to the same tab. Drag the stamp to move it.

Right-click a same-faction player and select **Social Credit**, or target them and type `/scs`. To reopen a known profile, type `/scs First Surname`. Each review is named and can be edited by its original character. Select the left or right half of a star to rate from 0.5 to 5. Half-star reviews require addon version 2.5 or later to sync. Players can read individual reviews as they arrive. The average appears once five accepted reviews are present.

Right-click a character’s name in chat and select **Open SCS**. Selecting **0 stars · Black Mark** asks for confirmation when you first give a player zero stars or lower an existing rating to zero. Zero-star reviews count toward the review average and SCS. You and your current guildmates see the black mark on the profile, player portraits, new chat messages, and Group Finder. Raising your rating clears your mark as the amendment syncs. Another qualifying zero can keep the player marked.

In version 2.8, the original author can choose **Delete review** from the review editor and write a fresh review later from the same character. Deletion removes the review from scores and clears its mark as it syncs. Peers on older versions may show the previous review until they upgrade and sync. Chat badges support Blizzard chat and Prat 3.0.

**Group Finder → Browse** shows locally available Social Credit Scores for eligible players and labels group listings with their leader's score. Hover over a listing for its review averages and counts, including named group members when available. An asterisk flags a provisional score. A dash indicates that a score is unavailable.

Use `/scs self` to view your personal stats. At level 60, it also shows your current dungeon or raid. Rates appear after Blizzard's damage meter makes a fight readable. Hover over an instance bracket to see duration-weighted lifetime DPS and HPS and their sample counts. Completed and unfinished runs contribute to lifetime averages for you and identifiable same-faction level-60 groupmates, including players without SCS. Duplicate witness reports of a fight count once. Verified clears count toward the combat score, which requires three qualifying clears in a bracket.

Open **Guilds** from the minimap menu to see known same-faction guilds on your server ranked by average member SCS. A guild appears once your client knows the scores of five distinct members. Membership and scores reflect the profiles your addon has observed.

Reviews sync by addon whisper between reachable players running SCS. Peers discover one another through guild, party, and raid messages or direct profile lookups. The shown count covers verified reviews on this client. The addon shares the owner's gameplay snapshot and instance fight reports on request. Dungeon and battleground counts cover observed completions. Your normal `/played` command refreshes the value if you want a newer snapshot.

**Total Reviews Given** counts distinct profiles reviewed by the character. Editing a review keeps the count the same. The value appears after syncing with that character on version 1.2 or later.

**Average Gear Roll** uses numeric group-loot results for equippable gear seen by the character's addon, including wins and losses. Typed `/roll` commands and pass choices are excluded. The sample count appears beside the average.

**Need-to-Greed** shows the counts of Need and Greed selections on equippable group loot, including main-spec and off-spec Need. For example, **3:1** means three Need selections and one Greed selection. Pass, Transmog, and typed `/roll` commands are excluded. Choice counts start with version 2.4 and are shared by the character's addon.

Reviews are backed up in game SavedVariables and by peers. The database is scoped to this installation's known account characters. It uses Forever's regionally unique two-part name as the stable key for addon messages. A character rename can appear as a new identity. Separate installs, unrecognized alts, modified clients, and colluding peers can bypass the local restrictions. Profiles, scores, player history, and local review editing work during combat and in instances. Peer discovery and sync use the channels the game allows. Saved reviews remain queued for peer replication when addon messaging is available again.

Gear scoring uses the original GearScoreLite coefficient lineage, following [TacoTip's Forever implementation](https://github.com/ssdeanx/TacoTip-Gearscore-TBC/blob/main/gearscore.lua) by AcidBomb, based on the original TacoTip by kebabstorm and GearScoreLite by Mirrikat45 and contributors.

The crest and frame art was generated with OpenAI ImageGen using the attached image as a style reference. The prompt requested a two-row sprite sheet with a neutral star crest, hammered iron, bronze, silver, ornate gold, and gold laurel frames, with crisp painted metal, warm highlights, and transparent portrait openings. Game textures are in `Media`.

For the profile refresh, built-in ImageGen produced a panoramic fantasy guild hall with maroon pennants, timber beams and warm edge lanterns, quiet slate and ivory parchment swatches, and a matched pair of filled brass and hollow brown stars with transparent backgrounds. The five new game textures are `GuildHall`, `StatsSlate`, `ReviewParchment`, `StarFilled`, and `StarEmpty`.

Run the offline integration checks with `python tests/check.py` and Python's `lupa` package.
