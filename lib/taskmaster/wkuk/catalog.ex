defmodule Taskmaster.Wkuk.Catalog do
  @moduledoc """
  The sketch catalogue: every sketch of every episode, in broadcast order.

  Seeded into `wkuk_sketches` by migration 7, and refreshed by migration 9 for
  rows nobody has edited. Beyond that it is **not read again**: editing this list
  changes a fresh database and, at most, the *unedited* rows of an existing one.
  A row someone has touched from the screen is never overwritten — see
  `Taskmaster.Wkuk.refresh_unedited_descriptions/0`. Titles are fixed in the UI;
  descriptions are editable from it, so a correction belongs there.

  Titles, order and descriptions come from the per-sketch synopses in Wikipedia's
  "List of The Whitest Kids U' Know episodes", condensed to one line each. Where
  that source says little, so does the description — "Zach suffers embarrassment
  at the office" is what it gives for *Peeing*, and inventing more would be worse
  than saying so. Edit those on the board. One description, *Jerkocaust*, is the
  owner's own wording.

  `youtube_url` is deliberately not seeded. There is no authoritative mapping
  from a sketch title to a video id, and a wrong link is worse than none; the
  board offers a YouTube search for the title until somebody pastes the real
  one.

  The format is one `season|episode|title|description` row per line, parsed at
  compile time, so a description cannot contain `|`. Order within an episode is
  the running order, and it is the order the unranked pile starts in.
  """

  @raw ~S"""
  1|1|iPod Shuffle|Woman mistakes her boyfriend's iPod Shuffle for a pregnancy test and pees on it
  1|1|Hitler Rap|Hitler stars in a rap video, "Triumph of the Ill"
  1|1|Timmy Poop|Timmy poops his pants in a boardroom meeting and throws it in the trash
  1|1|Alcoholics Anonymous|A drunk misunderstands the purpose of an AA meeting
  1|1|Abe Lincoln|Lincoln heckles a vampire Hamlet until John Wilkes Booth hammers him to death
  1|1|Pizza Bagels|Husband beats his wife for serving pizza bagels for breakfast
  1|1|Sexy Fawn|A fawn seduces hunters until the ranger steps in
  1|1|Slapping|Slaps, kicks to the balls and shirt wedgies are the new thing among friends
  1|1|Get a New Daddy|Song telling kids to frame their dad as a pedophile to get a new one
  1|2|Rock n Roll Indiana Jones|Indiana Jones protests the auction of Peter Frampton's guitar
  1|2|Let's Wake Up the Neighbors|Reggaeton video about disturbing the peace
  1|2|Movie Pitching Guy|A mail worker pitches movie ideas to studio heads and gets them psyched
  1|2|Abdell Drums|Timmy's parents are upset he bought a djembe drummer who's really a weed dealer
  1|2|Polite War|Redcoats try to fight the American army politely
  1|2|Burglar|A burglar's lawyer doesn't like his outfit
  1|2|Whip Boy|Annoying superhero Whip Boy answers the call to action
  1|2|Brothers in Arms|War movie trailer where three brothers get in a brawl
  1|2|Classroom|Kindergarten teacher plays a guessing game about a kid's mother dying in a car crash
  1|3|Peeing|Zach suffers embarrassment at the office
  1|3|Cubicle Guy|Boss bothers an employee with annoying questions and makes him draw what he did last night
  1|3|Pimp Pun Disaster|A pimp can't stop making "whore" puns while a nurse gives him his whore's status
  1|3|Whiskey|Trevor makes his own Super Size Me documentary, drinking only whiskey
  1|3|Time Travel Farmer|Two kids have fun with a time machine and a farmer
  1|3|Astronaut Mess|A late astronaut spills food on his crewmates
  1|3|Trevor Talks to the Kids|Trevor tells a second grade class conspiracy theories about President Bush
  1|4|Scarin' Babies|Trevor tries to scare a baby with college tuition and global warming, then just screams
  1|4|Saturday|Man-child David treats Saturday as a day to run amok with a bow and arrow
  1|4|Did You Used to Date?|Timmy assaults everyone who dated his girlfriend in high school
  1|4|Europeans|Re-enactment of Europeans meeting Indians in 1620 makes the Indians look like jerks
  1|4|Crying|Zach tells his girlfriend he has a brain tumor until the waiter offers a clam chowder that cures them
  1|4|White Castle|Zach tells Trevor about the time he ate at White Castle
  1|4|Europeans 2|Europeans meet Africans in 1769 and the Africans look like jerks
  1|4|Opposite Day Lawyer|A lawyer tells the jury Opposite Day has just begun
  1|4|Funeral Request|Zach makes a funeral request to Trevor
  1|4|Europeans 3|Europeans meet Martians in 3024 and the Martians look like jerks
  1|5|If You Think|A bunny, a dog and a man die in a fiery explosion if you obey the on-screen text
  1|5|Dating Game|Trevor hosts a dating game where the contestant gets only misogynistic answers from three bachelors
  1|5|Birds and Bees|Dad tells his son the gross facts of life
  1|5|Ghost Tea Bag|A fortune teller sees a ghost tea-bagging Zach
  1|5|Girl Sympathy|Women win each other's sympathy by comparing feminine issues
  1|5|Ghost Tea Bag 2|The fortune teller's prediction of Zach's promotion comes true
  1|5|You're Peeing on My Leg|Two English gentlemen reach an impasse in the park over one peeing on the other's leg
  1|5|John Wilkes Booth|Booth pelts Lincoln with a phone book, an orange and his shoe during a play
  1|6|Heaven|A man in heaven gets a fairy, a car and a puppy in a hatbox: "Ask your doctor about suicide"
  1|6|I Want to Kill the President|PSA about it being illegal to say on TV that you want to kill the President
  1|6|Bogey on My Six|Two pilots have an awkward talk about their friendship mid-air
  1|6|Slow Jerkin'|Darren creeps out his coworkers with mimed masturbation movements
  1|6|Race War|Dave warns Bill about a race war
  1|6|Bigfoot vs. Gravedigger|Two monster truck drivers meet at a house party and destroy the living room
  1|6|Sub Sandwich|Sailors on a submarine guffaw at the kind of sandwich a man has
  1|6|I Don't Know Bob|Two hunters talk their way through the aftermath of accidentally shooting another hunter
  1|7|Dear Black People|A six-year-old writes black people an apology for slavery and gets an angry reply
  1|7|Hot Air Balloon Poop Rope|An exchange student on a balloon ride with a British family suddenly needs the toilet
  1|7|Firing Squad|A firing squad shares one bullet so nobody feels guilty, and Trevor keeps shuffling the guns
  1|7|Accidental Puke|William throws up at the dinner table
  1|7|Gallon of PCP|College buddies meet in the park and Zach has a gallon of PCP
  1|7|Kool Aid|Epic movie trailer where a man turns the ocean orange
  1|7|Gross Out|Trevor grosses out an audience by drinking from buckets of disgusting substances
  1|7|Point/Counterpoint|A gun enthusiast and a host argue over gun control on a debate show
  1|8|Pie|Sam realizes he's been typing on a pie instead of a keyboard
  1|8|Acting Class|Timmy's homoerotic pantomime in acting class gets Darren failed for the year
  1|8|Demon Ouija Board|The demon Balthasar is summoned to run a ouija board at a girls' slumber party
  1|8|Flower Monster|A man follows rose petals upstairs with a baseball bat, expecting a flower monster
  1|8|Rape Role Play|A forgetful wife forgets the safety word during a rape role play
  1|8|Timmy Dance|Timmy dances seductively in his underwear
  1|8|Sam in the Bag|Two sitcom characters try to cover their tracks after smoking pot
  1|9|Pirates|The captain can't get his pirates' attention
  1|9|Glory Hole|A wife catches her husband at a glory hole
  1|9|Attention Guy|Zach needs constant attention, sings about ADD, then hangs himself
  1|9|Bank Heist|Bank robbers keep failing to pull off a heist
  1|9|Mrs. President|Perverted agents must behave around the first female president
  1|9|Mom and Dad's Divorce|In homeroom, Steven talks about his parents' divorce
  1|9|Tattoo Parlor|A drunk businessman asks a tattoo parlor for a bizarre tattoo
  1|10|Jim Bust - JISM|Trevor breaks down a producer's door to pitch with a perverse acronym
  1|10|We Gon' Make Love|R&B video where Trevor describes having sex with unconscious women
  1|10|Motorcycle Mama|A dad makes his son Billy disappear by saying "I don't believe in you"
  1|10|Jim Bust - Jim's Gay|Trevor asks Jim a trick question
  1|10|Timmy Dance 2|Timmy does a hoedown in his underwear
  1|10|Screamers|A sophomore sells freshmen new drugs: two "screamers" and a "small world"
  1|10|Mr. T Gets Cancer|Trevor and Timmy perform a short play about Mr. T getting bad news
  1|10|Jim Bust - Fart|Trevor and Timmy torture Jim with their farts
  1|10|Gun Face|Darren and Sam pretend to mutilate Zach while he's on the phone
  1|10|Mountain of Chairs|Timmy's parents leave him alone on his birthday but won't let him live on a mountain of chairs
  1|10|Jim Bust - Puppy|Trevor gives Jim a puppy, Wormy, who is terminally ill
  2|1|Sam's Nut I|Trevor points out that one of Sam's testicles keeps popping out
  2|1|The Dinosaur Rap|Trevor raps in a music video about getting high with dinosaurs
  2|1|Neil & Buzz|Two ghetto astronauts are about to land on the moon
  2|1|Sam's Nut II|At the movies, Trevor notices Sam's testicle hanging from his collar
  2|1|Racist Show Pitches|Zach pitches racist "fish out of water" TV shows and the network executive shoots them all down
  2|1|Air Dry|On a blind date, Trevor learns something unusual about his date
  2|1|Sam's Nut III|Sam gets embarrassed on the show "Double Date"
  2|1|Happier with your Mouth Open|A director gives odd direction to actors on a cop show
  2|1|Fart Dinner|At a restaurant, Trevor pretends to have gas
  2|1|Blind Not Blind|A doctor gives Sam glasses that show him how ugly his wife is
  2|2|String Pull|On a dinner date, Sam pulls a long string out of his teeth that is attached to his organs
  2|2|Oh Shit|Two peeping toms watching a stripper accidentally cause a chain of deaths
  2|2|The Never Song|Trevor sings a kids' song about staying out of trouble, including not making crystal meth
  2|2|Be a Cop|Recruitment trailer for a trigger-happy police force
  2|2|Cowboy|Cowboys put on campfire shows for each other and Timmy walks off in anger
  2|2|Feeler Doc|A doctor is terrified to touch a patient's lumpy testicle
  2|2|You Can See Me|Darren thinks he's invisible until he punches Sam
  2|2|Blue Whale Dick|Two sitcom teens have animal genitalia attached to their heads
  2|3|Instant Karma Bigot|Every time Zach says a slur, he gets what's coming to him
  2|3|Weird|At a gentleman's club, three guys learn what a stripper will do for money
  2|3|Joining the Army|Two enthusiastic guys describe the scenario they'd want in the army
  2|3|JFK Assassination|LBJ drops in on Oswald at the Book Depository and they argue over how to do the assassination
  2|3|Saggy Sammy|Little Kevin shows his parents a drawing of an elephant
  2|3|George Lucas|A teenager pitches Star Wars VII to George Lucas, who dies of excitement
  2|3|The America Song|A country singer is "totally gay for America" and Uncle Sam
  2|4|Guillotine Days|Marie Antoinette is asked to recite the alphabet after beheading to settle a bet
  2|4|Forever Puppies|A business that keeps cute puppies from turning into dogs
  2|4|Francis Scott Key|In prison, Francis Scott Key wants to write "The Star-Spangled Banner"
  2|4|Mount Everest|Four-act sketch about an adventurer blackmailed by a crafty diamond thief
  2|5|Reverse Psychology|Sam becomes annoying after learning about reverse psychology
  2|5|You Son of a Bitch|Trevor keeps switching sides to kick whichever man is guilty of something worse
  2|5|I Teached A Whale|A teacher chases proof against a kid who says he taught a whale to jump out of its tail
  2|5|The Raddest Kid Ever|Billy's dad thinks his son looks amazing with a gun in his hand
  2|5|Religious Cult|Trevor and Sam ponder the religious cult they're in
  2|5|Nail Gun|Brothers kill Sam with a nail gun, revive him with the Necronomicon, and get caught by their parents
  2|5|Irresponsible Television|Kids' shows keep getting pulled off the air for reckless irresponsibility
  2|5|Aren't You Lucky|Trevor's song about God is sung in other countries
  2|6|Forest Whitaker|Trevor mistakes Zach and Timmy for Forest Whitaker
  2|6|Manatee Finger Bang|A morose king is offered a "mermaid" to cheer him up
  2|6|Office Head Explosion|Coworkers mess with Darren's head while he sleeps and it explodes
  2|6|Period Sketch|Teenage Margaret dodges the Fairy of Womanhood until Rationality steps in
  2|6|Ninja School|Nobody shows up for the first day of Ninja School, or did they?
  2|6|Our Label is Run by Homos|A band's debut CD announces everyone at the label is gay, leading to an awkward press conference
  2|7|Falling Ladies|Zach alerts Sam and Trevor to something happening outside and it ends bloody
  2|7|Tar Toast #1|A screenwriter tries an unusual hors d'oeuvre at a party
  2|7|Successful Relationship|Harold writes a how-to book based on his volatile marriage
  2|7|Tar Toast #2|The screenwriter has to pitch to the man who tricked him into eating street tar
  2|7|Underwater|Nancy's dad shoots down her wish to live underwater with her new boyfriend
  2|7|Shark Man|Annoying superhero Shark Man has to manually refill his lungs with air
  2|7|Drunk Dad|Susie's dad comes home hammered during her birthday party
  2|7|Time Travel Friends|Two guys go back in time to stop 9/11
  2|8|Take My Face Off|A patient makes an odd surgery request
  2|8|Boiler Room|A boiler repairman has no sympathy for drowning yacht passengers and criticizes the crew's maintenance
  2|8|Driving Instructor|Audio sketch: a driving instructor gets friendly with his student
  2|8|Marijuana To Go|A commercial ends before it even starts
  2|8|Alzheimer's|Sammy messes with his grandma
  2|8|Auto Erotic|Trevor regrets how he died and God gives him a second chance at the wrong time
  2|8|Bear Problems|The press secretary hosts a conference about bears on the moon
  2|8|Good Morning Dad|A boy's attempt to bond with his dad backfires
  2|9|Invincible Kid|Trevor gives a kid a pep talk
  2|9|Sniper Business|A war-hungry boss deals with a rival company's rooftop sniper by taking him out himself
  2|9|Dogs Love Boobs!|Blackout about dogs loving boobs
  2|9|Greatest Conductor|An armless conductor conducts with his feet
  2|9|Alcoholic Husband|A wife keeps catching her husband drinking beer in different ways
  2|9|The Complete Human History of the Last 10,000 Years in Seven Seconds|The moral: you will get stabbed if you have gold
  2|9|Office Insubordination|Zach and Sam get on better with the boss than newbie Darren does
  2|9|Entertainment Today|A tan anchor reports on Steve Buscemi
  2|9|T2 9-1-1|Audio sketch: a caller's emergency resembles the plot of Terminator 2
  2|9|Cloud Watching|Sam and Trevor look at cloud formations
  2|9|Virtual Knuckle Sandwich|Angry Clyde takes Mabel to Virtual World to give her a knuckle sandwich
  2|9|Video Time Capsule for the Year 3000|Capitalism still reigns
  2|9|Homeless Love at First Sight|Trevor and a homeless woman feel an instant connection
  2|10|Blind Guys|Blind stand-up comedians find telling jokes is never routine
  2|10|Whirlpool|Gordon and Candice get caught in a whirlpool and an argument
  2|10|Line Leader|A new line leader prepares his class for an epic fight with the fifth-graders
  2|10|Dolphin Song|A guitarist tries to work his pet dolphin into his open mic act
  2|10|Sonic the Hedgehog Gets Mugged|A mugger punches Sonic and his coins scatter like rings
  2|10|Zach Dating Karen|Zach asks the audience to settle arguments with his girlfriend
  2|10|The Dinosaur Rap (Live)|Trevor raps live about getting high with dinosaurs
  3|1|Chaplin|Soldiers in a 1940s war movie meet Charlie Chaplin, or is it Hitler?
  3|1|Bible Stories|Luther B. promotes his "cool" version of the Bible on video
  3|1|Feline Delights|A seductive cat food ad
  3|1|Dumb Newscast|A music TV newscaster reports on an alien abduction and Ozzfest
  3|1|Car Dealership|A car dealer stars in a commercial with his unenthusiastic sons
  3|2|Little Rascals|Two men disguised as one tall person get into a bar and meet another tall person
  3|2|Call of Duty|During a multiplayer game, Dabears needs a sandwich
  3|2|The God Says Song|Trevor sings about what he's heard from God over the years
  3|3|Water Balloons|A young businessman introduces water balloons to a quiet Wild West town
  3|3|Hot Dog Timmy|Timmy explains to his doctor why he eats at least one hot dog a day
  3|3|JJ Marvin|Punk rockers aren't sure what to make of JJ Marvin's act
  3|4|Foot Touch|Two homophobic men cause a stir at dinner
  3|4|Bad Panda|Terry wants a zoo job beating up misbehaving animals
  3|4|Runway|Women at a fashion show are very enthusiastic about the new fashions and glitter
  3|4|Gandalf|The Fellowship angrily confronts Gandalf for not using the giant eagle sooner
  3|5|Presidential Props|New debate rules throw off an unprepared senator
  3|5|Island Cannibal|Two stranded guys resort to eating each other
  3|5|Helicopter Door|In Vietnam, one soldier tells another to close the helicopter door
  3|5|Super Dog|Presidential Props Part 2: the debate party continues at the club with a song
  3|6|Trent Reznor|Trent Reznor's arrogant ex visits just to torture him into writing another Grammy-winning album
  3|6|Homeschool|Caleb doesn't take homeschooling seriously
  3|6|Telekinesis|Sam masters telekinesis and knows just what to use it for in bed
  3|6|Dog Park|Perverts with x-ray glasses can see through dogs' clothing
  3|7|Asian Hooker|A CEO brings a prostitute who tried to steal his wallet into a meeting, then her pimp arrives
  3|7|Skatefall|Mr. McGillicuddy gets fed up with skateboarding
  3|7|Earthquake|A news anchor swears on air during an earthquake and is put on trial, until the quake stops
  3|7|Boner Song|Cast song about things that are hard or unadvised to do with a boner
  3|8|Tit Slap|At a party of mostly black people, Trevor obeys the lyrics of a crunk song
  3|8|John Hancock|Who really was first to sign the Declaration of Independence?
  3|8|Bad Dominatrix|A dominatrix shows a newbie the ropes
  3|8|Bobo the Monkey|A NASA scientist tries to make his team cut ties with Bobo, the first monkey in space
  3|9|Horses Love|Darryl tries to arouse his horse for insemination and a stegosaurus poster does the trick
  3|9|Loveliest Bride|Blood-stained Candice will stop at nothing to see the chick flick The Most Loveliest Bride
  3|9|Fight Club|Trumeter's Fight Club-obsessed boss goes down with one punch
  3|9|The Popcorn Factory Sketch|Coworkers argue whether a girl with testicles but no penis would be hot, at an office that turns out to be a popcorn factory
  3|10|Shoshon|Shoshon the White Tiger King wants to keep the brown tigers out of Animalia
  3|10|Lawnmower Dad|A dad covers up a lawnmower accident by faking the dog's suicide
  3|10|Elves|Trevor and Sam play with an x-ray machine while waiting for the doctor
  3|10|Blue Hair Timmy|After dyeing his hair, Timmy gets hit by a car
  3|11|Shitchest Boner Neck|Three ambassadors struggle to negotiate with two peculiar, gross aliens
  3|11|Crack|In 1984, two hip-hop posers turn a black man into a crack dealer
  3|11|What is it Baby|Sarcastic parents chide their crying baby for waking them at night
  3|11|Last Action Hero|A realistic twist on a scene from the movie
  3|12|Yellow Mustard-ed|A hidden-camera show, You've Been Yellow Mustard-ed!, is successful and controversial
  3|12|Kindergarten Cons|Movie trailer where five of the toughest convicts are sent to kindergarten
  3|12|Table Monster|A husband has mastered getting out of dinner with his annoying wife and her annoying best friend
  3|13|Genie|A kid's genie has to grant his wishes: kill his teacher, have sex with a 12th grader, become President
  3|13|Epilepsy Test|A test for whether the viewer has epilepsy, with a loading bar
  3|13|Bad Employee|A sick fast-food employee vomits in front of customers and gets fired
  3|14|Grapist|A boardroom finds a grape soda ad questionable because the mascot is named the Grapist
  3|14|Lottery|Sam stupidly spends his lottery winnings on lottery tickets
  3|14|Ronald Reagan|Reagan would rather talk movies than politics, and Hinckley gets distracted talking movies too
  3|15|American Suicide|Contestants on an American Idol-style show compete to kill themselves creatively
  3|15|Anarchy|Barry is the only rational thinker on a team of anarchists
  3|15|RC Glow|An executive has an idea for RC Cola
  3|16|Courtroom Stripper|A stripper called to testify ends up entertaining the court instead
  3|16|Dad Story|Dad tells his daughter how she came along while the Jolly Green Giant shows up on the roof
  3|16|Life Goes Alien|Aliens mock a family they meet
  3|17|Wheel of Money|A game show ripoff plagued by copyright issues, dismemberment and decapitations
  3|17|Butler Sketch|Five seconds with a butler on his first arrival in Haiti
  3|17|Hiking Documentary|A hiker is left to die while a documentary is filmed
  3|17|Back Seat|Two Socialist hoodlums love the back seat of the bus
  3|18|End of Space|A space traveler gives unnecessary narration while unusual things happen beyond space
  3|18|Donkey Dad|Dad has to explain to his daughter what he was doing with the donkey
  3|18|Casual Friday|Brian isn't comfortable with Steven's shirt for Casual Friday
  3|18|Hippo in the City|A hippo wanders through New York City
  3|19|Jerkocaust|Nazis look for jerks
  3|19|Trophy Coach|The losing coach gets more respect than the winner by giving every player a trophy
  3|19|Helicopter Wife Cheating|A news helicopter pilot recognizes his wife's car on the freeway
  3|20|Another Astronaut Sketch|The moment before the Challenger takes off
  3|20|Not Particularly Sure|Outsourcing leaves a company little to do at headquarters
  3|20|Maroon President|The president thinks he's discovered a new color, or has he?
  3|20|Bathroom Camera|At a christening party, Timmy shows off the bathroom cameras he installed
  4|1|Grandma's Cookies|Blackout: a scary ad for the Hazy Memories Nursing Home
  4|1|Alien Autopsy|The alien turns out to be a piñata filled with Reese's Pieces
  4|1|Jaws|Everyone thinks there's a bear in the ocean but it's a shark, and Sailor Flynn gives a long speech about sharks
  4|1|Love at First Sight|Stan meets Stacy and Betty at a party but can't get them to kiss each other
  4|1|We Got a Runner!|A mother has trouble delivering a baby: "We got a runner!"
  4|1|Santa Clause|Santa gets stuck in the chimney with his pants down
  4|1|Sex Robot|A horny robot is taken to jail, put on trial and sentenced to hanging
  4|1|Mouth Stuck Open|The doctor doesn't think Trevor's mouth is stuck open
  4|1|Rip Your Dick Off|A store employee warns a customer against using a strong vacuum for oral sex simulation
  4|1|Barf Museum|Two fathers at a kids' museum about regurgitation decide to ditch their kids
  4|2|Hand Pee|Dave hides that he loves touching his own urine and excrement
  4|2|Senator Clint Webb|A generic campaign ad
  4|2|Changing Channels|Darren apologizes in advance for a segment that turns into a Saturday Night Live parody
  4|2|Alive Dicks|Stranded in the frozen north, the cast resort to cannibalism and only Sam and Timmy would eat a certain leftover body part
  4|2|Dr. Kyle|Dr. Lewis is scared to tell a child about his condition but Dr. Kyle isn't
  4|2|You Talkin' to Me?|A man shoots his horse while practicing De Niro and Eastwood impressions and makes his daughter help
  4|2|Barney the Bear|A motorcycle-riding bear escapes the circus to get revenge on an old foe
  4|2|Bike Up the Ass|A crash between a businessman and a cyclist turns into road rage that goes all the way to court
  4|2|Titopotomus|A slew of stupid made-up strip club names, continuing over the credits
  4|3|Spaghetti Dinner Date|A twist on the famous Lady and the Tramp scene
  4|3|Mission Impossible|A mission briefing includes a bulldog and a handjob
  4|3|Hamster Death|A dad teaches his son about death when the hamster dies and the Grim Reaper eats its body
  4|3|Walk of Shame|A teacher corrects a student's oral report full of Wikipedia info
  4|3|Sam's Muscles|Dario thinks meeting the parents will go well
  4|3|Boner Wedding|A con artist ODs on male enhancement pills while posing as a bride
  4|3|Scrubbly Bubbles|A disinterested CEO messes with his company's ads
  4|3|Trench Big Mouths|Soldiers ham it up when they get shot, except Timmy
  4|3|Dad Fight|Jerry's opponent goes down with one punch
  4|3|Pet Heaven|After dying of carbon monoxide poisoning, Trevor ends up in the wrong heaven
  4|4|Old Man Winters|Trevor and Darren tamper with an old man's will
  4|4|Chicken Not Kitten|A health inspector suspects the restaurant "It's Not Kittens, It's Chicken" of serving cat and finds it serves dog
  4|4|Computer Jerk Off Dad|Dad jerks off when the family goes to the store
  4|4|Kid Beer|A brewing company markets beer to children
  4|4|Booger Blasters|A new squirt gun that squirts boogers
  4|4|Walt Whitman|PBS reads Walt Whitman's teenage diary and finds out how obsessed he was with breasts
  4|4|Insult Restaurant|New waiter Timmy insults customers at Jack Off's Slop Shop and comes off as flat-out vulgar
  4|4|Moon Landing|A student asks his teacher who shot the Moon landing footage
  4|5|Poseidon Devil Spaghetti|Poseidon and the Devil eat spaghetti together
  4|5|Pussy Salad|Two men loudly say a salad tastes like pussy to expose a coworker's son for eating pussy
  4|5|Charles Manson|A shopping channel sells Charles Manson's artwork
  4|5|Jumbotron|A basketball jumbotron keeps zooming in on Timmy
  4|5|Clarence McKenah|Black and white footage of Clarence McKenah punching people
  4|5|Kid Mechanic|Greg's kid is unconscious on the playground so he takes him to a mechanic
  4|5|Timmy Talk|The cast tease Timmy about his new TV pilot that doesn't exist
  4|5|Bananas|Trevor smokes a banana peel
  4|6|John Cleese Sketch|Trevor and Sam perform a sketch sent to them by John Cleese
  4|6|Planet Earth Choke|Pilot for a new nature show hosted by Sam
  4|6|Dad Wired Shut|A dad's mouth is wired shut so he has to eat in a special way
  4|6|A Is For|An author's crime novels are titled one per letter of the alphabet, and she is exasperated and depressed
  4|6|We Live in Garbage|A homeless man yells at a camera about being evicted, but there's no camera, wife or son
  4|6|50 Cal Bar|Zach brings a World War I machine gun into a bar
  4|6|Cumfetti|Timmy ejaculates confetti and impregnates his wife with the world's first cumfetti baby
  4|6|Juror|Trevor tries to evade jury duty
  4|7|Silver Street Performer|A street performer acts like a robot
  4|7|Cash Quiz|Osama Bin Laden hosts a game show to apologize for the World Trade Center attacks
  4|7|Great Grandmas|Darren complains the porn he bought is about great grandmas, not grandmas who are great
  4|7|ButterBar|A fast food chain is forced to sell a stick of butter and a kid gets sick eating two
  4|7|History Reset|Sam resets his browser history after jerking off
  4|7|Corporal Punishment|Many military men get rank changes
  4|7|Secrets of the Pyramids|Talking pyramids gossip about the other wonders of the world
  4|7|Video That Makes You Gay|Sam tries to convince Trevor to watch a video that supposedly makes you gay
  4|8|Valentines Day|Trevor is caught masturbating to baby pictures when his wife walks in
  4|8|A Simple Chore|Michael Moore makes a documentary about his wife not doing the dishes
  4|8|Stock Watch|Ad for a book that supposedly helps you in the stock market
  4|8|Chad's Rad (Brian the Faggot)|Chad makes a school project video about a classmate
  4|8|Pun Army|Police officers make puns before raiding a zoo
  4|8|History Network|Trevor shows his new pilot to the History Network
  4|8|Astronaut Pranks|Astronauts try to prank mission control
  4|8|Hunting Housecats|Mini-documentary about two hunters who hunt housecats
  4|9|Babe Magnet|Trevor and Darren build a machine that magnetically attracts babes
  4|9|Hell's Kitchen|Satan orders his chefs to cook disgusting food
  4|9|Honey I'm In Therapy|Sam vents about his childhood to his therapist
  4|9|One of You Is|A policeman tries to expose unwelcome guests on a space colony that only allows humans, not cyborgs or ghosts
  4|9|Freaky Thursday|A dad convinces his son's girlfriend that they switched bodies
  4|9|Gay Football|Scenes from the Gay Football League, from press conference to locker room
  4|9|Genetic Pigs|A scientist develops a pig that maximizes meat production
  4|10|Halloweiner|Kids show off Halloween costumes and the teacher sends the pirate and the cowboy to the principal for swearing
  4|10|Landmine Factory|Zach shows Trevor the ropes at the landmine factory
  4|10|The Pope|The new pope is shown a video made by the old pope
  4|10|Animals Anonymous|A meeting of the Animal Lovers Anonymous club
  4|10|Job Interview Mess Up|A demonstration of what not to do at a job interview
  4|10|First Person Shooter|The cast play a first person shooter and have some troubles
  4|10|Things We Need|The cast tell the audience what items they need for future sketches
  5|1|Baked Beans|Timmy works at a call center
  5|1|Little Hitler|In a black-and-white sitcom, young Adolf Hitler is a local community hero
  5|1|Songs of Olden Times|Trevor sings songs about outdated social norms
  5|1|War Letter|A US soldier in Vietnam bleeds out while writing a letter to his wife
  5|1|Finger Ring Friends|Super powered finger rings have never been so fun
  5|1|Civil War on Drugs Part 1|Sam and Trevor learn about marijuana in the antebellum South
  5|2|Slow Mo Squirrel|A squirrel jumps into Trevor, Sam and Darren's car
  5|2|Wedding Flip Flop|Sam discusses with Darren whether to marry his girlfriend
  5|2|Ocean 2.0|A tragic oil spill is sold as an exciting new time for the planet's ecosystem
  5|2|Anne Frank|A soldier finds a young girl's private diary and decides to sell it
  5|2|First Date|On a first date, a man considers ordering dog poop
  5|2|Old Folks Home|Trevor raps about hating nursing home visits until he learns how many drugs the seniors are prescribed
  5|2|Civil War on Drugs Part 2|The Civil War begins and Sam and Trevor think marijuana has been made illegal
  5|3|The Jizzle|ShamWow parody selling a rag made to clean up semen
  5|3|John Williams|John Williams spends his day singing his music
  5|3|Ants|A dad tries to discipline his family, who escape by pretending ants are carrying them away
  5|3|Darren and the Giraffe|The cast promise to edit a giraffe under Darren on the green screen, then edit in a mostly naked man
  5|3|Herpes Commercial|Infomercial for a cream that tricks partners into thinking you don't have herpes
  5|3|Bikini Day|Kids tell their dad it's bikini day at the zoo, a trick to stage an intervention
  5|3|Civil War on Drugs Part 3|Sam and Trevor stage a legalization protest on the day and place of the Battle of Bull Run
  5|4|Firetruck Pullover|Sam is pulled over by a firetruck because his car is on fire
  5|4|Spanking Dads|Dads discuss their increasingly violent acts of domestic violence
  5|4|Careful Commandos|SWAT commandos plan to announce every time a criminal points a gun at them
  5|4|MacDougal|A pub runs Lady's Night, Black Night and White Night, each with discounts
  5|4|Teacher's Union|A group of teachers invent school
  5|4|Didgeridoo|Saul Rosenberg has a didgeridoo album
  5|4|Digging People Up|A man who lost his hardware store threatens to dig up people's relatives unless they send money
  5|4|Civil War on Drugs Part 4|Sam and Trevor enlist in the Confederacy, believing they're fighting to legalize marijuana
  5|5|Black Light|Young Billy gets a blacklight for his room and doesn't realize what it will reveal
  5|5|Nic-O-Dick|Ad for a nicotine device shaped and used to resemble oral sex
  5|5|Stork Factory|A baby factory worker sends babies to the wrong places, then starts killing them when confronted
  5|5|Nerf Nuke|Nerf releases the Nerf Nuke and kids buy them to become neighborhood superpowers
  5|5|Civil War on Drugs Part 5|Sam and Trevor's company dies in battle and their photos make them war heroes
  5|6|God Wants You to Wear a Hat|Trevor sings that most major religions have a special hat, so God wants you to wear one
  5|6|Dad Will Take Care of It|A dad complains his family expects him to do all the work while they offer to help
  5|6|Zombie Press Conference|The Pentagon says zombies eventually turn back into humans, but people who killed them won't be tried for murder
  5|6|Bad Drivers|A student driver won't brake for people having a picnic
  5|6|Hot Sister|A dad and son discover a family member has gotten hot
  5|6|Milfy Mom|Billy's mom reads his chat, thinks MILF is a compliment, and he has to explain it
  5|6|Making Animals Kiss|A TV show makes animals kiss
  5|6|Civil War on Drugs Part 6|Sam, Trevor and Doug camp out and are captured by American Indians
  5|7|Going Home Alone|A man rigs his house with Home Alone booby traps, calls 911 to say he'll kill himself, then shoots himself
  5|7|Liquor Store Robbery|Homeless Joe holds a businessman at gunpoint and makes ridiculous requests
  5|7|Pledge of Allegiance|The Pledge of Allegiance is more unsettling than you remember
  5|7|Dead Teacher|A student's attempt to kill his teacher escalates until everyone is shooting each other and the school blows up
  5|7|Escape Artist|A local escape artist has been underwater for 17 hours
  5|7|Civil War on Drugs Part 7|The tribe throws a frat party and Sam and Trevor ambush Ulysses S. Grant on peyote
  5|8|Timmy Future|Timmy invents a time machine and accidentally erases himself
  5|8|Baby Traits|A couple picks their baby's traits, including race and disability, from a black, gay doctor missing a leg
  5|8|1000 Dice|Commercial for a board game, Crazy Chase, that contains 1000 dice
  5|8|Bill's Back from Vietnam|Bill returns from Vietnam much more Vietnamese than his friends remember
  5|8|Horse Announcer|An announcer lists ridiculous horse names
  5|8|Civil War on Drugs Part 8|Sam and Trevor talk with Ulysses S. Grant and become sympathetic to the Union
  5|9|Worst Orchestra|A narrator lists the worst orchestras of all time, then trash talks Philadelphia on behalf of New York
  5|9|Come Down Here|Jason discusses with his mom the semen all over his yard sale boxes
  5|9|Spaghettio's|A man discovers Spaghettios in his blood transfusion
  5|9|Homeless Show|A show about how homeless people can live better gets bad ratings
  5|9|Joe Has Syphilis|Joe tells his exes he has syphilis, but he doesn't
  5|9|Cactus Wasp|A glitter-covered man and his clown wife have an important discussion about abortion
  5|9|Inappropriate Dinner Conversation|Sam keeps saying inappropriate things over dinner with Trevor
  5|9|Civil War on Drugs Part 9|Sam and Trevor avoid execution by giving General Grant intel and switching to the Union
  5|10|Mom Phone|Sam picks up the phone for his mom, but she doesn't hear him
  5|10|It Was Pretty Good|The news replaces a veteran reporter with young attractive people, and one reports on the Republican debate: "it was pretty good"
  5|10|Sophomores|A girl comes out as a lesbian to parents who think it's a phase, then her twin brother comes out and they threaten to disown him
  5|10|Civil War on Drugs Part 10|Sam and Trevor beat the Confederacy, learning the war was about slavery and marijuana was legal all along
  """

  @sketches @raw
            |> String.split("\n", trim: true)
            |> Enum.map(fn line ->
              [season, episode, title, description] = String.split(String.trim(line), "|")
              {String.to_integer(season), String.to_integer(episode), title, description}
            end)
            |> Enum.group_by(fn {season, episode, _, _} -> {season, episode} end)
            |> Enum.flat_map(fn {_key, rows} ->
              Enum.with_index(rows, fn {season, episode, title, description}, index ->
                %{
                  season: season,
                  episode: episode,
                  position: index,
                  title: title,
                  description: description
                }
              end)
            end)
            |> Enum.sort_by(&{&1.season, &1.episode, &1.position})

  @doc "Every sketch, in broadcast order."
  def all, do: @sketches

  @doc "How many sketches the catalogue holds."
  def count, do: length(@sketches)
end
