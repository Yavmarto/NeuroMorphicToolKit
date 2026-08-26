# NC-NL introduction email

## Aan wie, en in welke volgorde

**1. Bas van der Starre — Kwartiermaker Neuromorphic Technologies, Digital Holland.** Dit is de
persoon wiens functie letterlijk is om dit ecosysteem op te bouwen. Een kwartiermaker krijgt betaald
om te weten wat er in het veld gebeurt en wie wat bouwt; een ongevraagd aanbod van een werkende
toolkit is voor hem nieuws, geen ruis. Stuur naar `nc-nl@digital-holland.nl` met **"T.a.v. Bas van
der Starre"** bovenaan, en leg daarnaast een LinkedIn-connectie aan met een verwijzing naar de mail.

**2. Johan Mentink (Radboud Universiteit)** — het boegbeeld van NC-NL en coördinator van het
white-paper kernteam. Stuur hem een dag later een vrijwel identieke mail op zijn RU-adres (te vinden
op zijn medewerkerspagina). Een naam reageert waar een algemene inbox getrieerd wordt.

Verdere namen, alleen relevant als je verder komt: **Frits Grotenhuis** (directeur/bestuur Digital
Holland) en **Tijs Koops** (programmamanager internationalisering en innovatief mkb).

**Nooit "Beste lezer".** Dat leest als een nieuwsbrief en signaleert een massamailing — precies het
tegenovergestelde van wat je wilt. Heb je echt geen naam, gebruik dan "Beste NC-NL-team".

## Onderwerpregel

Primair:

> `Proof of concept gebouwd op de knelpunten uit het NC-NL Action Plan`

"Proof of concept" is bescheidener en nieuwsgieriger dan "toolkit", dat als verkoop kan lezen. Het
noemen van hun eigen document is wat de mail geopend krijgt: het zegt dat je hun werk hebt gelezen,
niet dat je iets aanbiedt.

Alternatief, als je de drempel nog lager wil leggen:

> `Proof of concept op de NC-NL knelpunten — demo van 3 minuten`

Het noemen van de lengte vertelt ze precies wat het ze kost om te kijken. Werkt goed bij mensen met
een volle agenda.

## Verder

**Voeg niets bij.** Eén link. Een cv als bijlage maakt er een sollicitatie van, en dat is dit niet.

**Voor verzending:** zet de video **unlisted** online en controleer dat de beschrijving niet meer
naar de GitHub-repository verwijst (al aangepast in `youtube-description.md`).

**Accuratesse:** deze versie noemt niet meer welke targets wél en niet draaien. Dat detail staat nu
alleen nog in de videobeschrijving — vul die dus in vóórdat de link de deur uitgaat.

---

## Dutch — FINAL (approved 2026-08-24, send as-is)

**Onderwerp:** `Proof of concept gebouwd op de knelpunten uit het NC-NL Action Plan`

> T.a.v. Bas van der Starre
>
> Beste Bas,
>
> De afgelopen zes maanden heb ik naast mijn werk een proof of concept gebouwd dat direct voortkomt uit jullie eigen documenten. Het white paper, de roadmap en het Action Plan benoemen telkens hetzelfde: hardware opzetten is moeilijk, drivers, simulators en remote servers werkend krijgen kost weken, en er is nauwelijks standaardisatie of gebruiksvriendelijke software. Ik liep daar zelf tegenaan, en ben gaan bouwen.
>
> Demo van drie minuten: [video-URL]
>
> Kort gezegd: je zet de server makkelijk op via de app (desktop of mobiel), ontwerpt een netwerk, traint het één keer, en draait het daarna op verschillende platformen — waaronder een echte Akida-chip — zonder zelf SDK's, simulators en serveromgevingen aan elkaar te knopen. Een complete workflow of experiment, inclusief model en resultaten, is in één keer te delen, zodat iemand anders het kan repliceren.
>
> Dat raakt aan drie van de vier punten onder "market driven application lab" in het Action Plan: benchmarkmethodieken, toegang tot hardware, en open developer-toolsets die de drempel tot adoptie verlagen.
>
> Naar aanleiding hiervan kom ik graag met jullie in contact over het volgende:
>
> Ten eerste een gesprek van een half uur over de toolkit en over waar het veld nu staat. Ik ben benieuwd of dit iets oplost dat jullie herkennen, of dat ik iets over het hoofd zie.
>
> Ten tweede: welke mensen of organisaties binnen de alliantie zouden dit moeten zien? Ik denk zelf aan partijen als Innatera en Axelera AI, die beide neuromorphic hardware ontwikkelen, maar jullie overzien het veld beter dan ik.
>
> Ik oriënteer me op een rol in dit vakgebied in Nederland, maar dat is niet waarom ik schrijf — de toolkit stel ik los daarvan graag beschikbaar.
>
> Met vriendelijke groet,
>
> Yoshi Martodihardjo-Bink
> +31 6 55585355
> yoshi.martodihardjo@gmail.com

**Dependency:** this version no longer lists which targets run. That detail now lives *only* in the
video description, so make sure the description is filled in before the link goes out.

---

## English — only if they route it to a non-Dutch reader

**Subject:** `Proof of concept built on the bottlenecks in the NC-NL Action Plan`

> Dear [name],
>
> Over the past six months I have built, alongside my job, a software platform that comes directly out of your own documents. The white paper, the roadmap and the Action Plan all name the same thing: hardware is hard to set up, getting drivers, simulators and remote servers working takes weeks, and there is little standardisation or user-friendly software. I ran into that myself, and started building.
>
> Three-minute demo: [video URL]
>
> In short: you design a network in the app, train it once, and then run it on several platforms — including a real Akida chip — without having to wire together drivers, simulators and server environments yourself. The server sets itself up. A complete experiment, model and results included, can be shared in one piece so that someone else can repeat it.
>
> It is explicitly a proof of concept: three software runtimes plus Akida genuinely run; the others — including PYNQ-Z2 and Loihi — are at the code-generation or integration stage.
>
> That touches three of the four bullets under the Action Plan's market-driven application lab: benchmark methodologies, access to hardware, and open developer toolsets that lower the barrier to adoption.
>
> Two things I would like. First, half an hour to talk about the toolkit and about where the field stands — I would like to know whether this solves something you recognise, or whether I am missing something. Second, which people or organisations within the alliance should see this? I am thinking of companies like Innatera and Axelera AI, which both develop neuromorphic hardware, but you have a far better view of the field than I do.
>
> I am looking for a role in this field in the Netherlands, but that is not why I am writing — I would offer the toolkit regardless.
>
> Best regards,
> Yoshi Martodihardjo-Bink

---

## Why it is built this way

- **Their documents first, your project second.** The opening sentence is about their analysis, not
  your achievement. The whole mail then reads as a response to them rather than a pitch at them.
- **The video before the description.** They will click it before reading paragraph three.
- **Claims match the verified status.** Three software runtimes plus Akida; everything else named as
  integration in progress. Nothing here can be contradicted by someone who actually tries it.
- **"Proof of concept" does the whole job.** Three words set the expectation; the sentence that
  follows says which parts run and which do not. Explaining your documentation conventions to a
  policy reader was over-answering a question nobody asked — save it for the conversation.
- **Two asks, both cheap.** Half an hour, and a question that is literally their function.
- **No CV in the email.** Nobody at NC-NL knows you study, so "dit is geen studieproject" was
  answering an objection that was never raised — and raising it plants the idea. The opening line
  already says "naast mijn werk", which tells them you are employed without listing anything. The
  eight years and the lead role land later, on the CV, when someone has asked for it.
- **The description is written for a policy reader.** No NIR, no runtimes, no SSH, no code
  generation. It echoes their own bottleneck vocabulary — drivers, simulators, serveromgevingen —
  and the scope limit gets its own short paragraph so it reads as candour rather than a caveat
  buried mid-sentence. The technical detail belongs in the conversation they will hopefully book.
- **No attachments.** If they want the CV they will ask, and then you are answering a request.

## Follow-up

Once, after eight to ten working days:

> Hoi [naam] — even een korte herinnering aan onderstaand bericht, mocht het ondergesneeuwd zijn. Ik ga graag in gesprek, maar mocht dit niet aansluiten dan hoor ik dat ook prima. Beide antwoorden helpen me verder.
