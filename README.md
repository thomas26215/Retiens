# Retiens

App Flutter de **rappels de révision** (pas de flashcards). Tu ajoutes un sujet « étudié aujourd'hui » (ex. *Chapitre 1 : fondamentaux*), l'app te le rappelle le lendemain, puis tu notes chaque révision (**Oublié, Difficile, Bien, Facile**) : le rappel suivant est d'autant plus loin que la révision s'est bien passée.

## Lancer sur le téléphone (Android)

Téléphone branché en USB, débogage USB activé :

```bash
flutter test
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

L'app « Retiens » apparaît alors dans le tiroir d'applications et fonctionne sans le PC. Pour développer avec rechargement à chaud : `flutter run`.

> `--target-platform android-arm64` : sans ce flag, le build échoue à l'étape `stripReleaseDebugSymbols` (bibliothèques armeabi-v7a / x86_64 manquantes). arm64 couvre tous les téléphones récents.
>
> `flutter analyze` plante si le chemin du projet contient un accent (`Téléchargements`) : c'est un bug de l'analyseur, pas du code. Déplacer le dossier ou analyser une copie.

L'APK est signé avec la clé de debug : suffisant pour un usage perso, pas pour le Play Store.

iOS : pas de dossier `ios/` (impossible à compiler sous Linux). Sur un Mac : `flutter create --platforms=ios .`.

## Réglages Android pour les notifications

Déjà appliqués dans `android/`. Rappel de ce qui a été ajouté pour `flutter_local_notifications` :

`android/app/build.gradle.kts` :

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`android/app/src/main/AndroidManifest.xml` : avant `<application>` :

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

et dans `<application>` :

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

Le fuseau est fixé à `Europe/Paris` dans `lib/services/notifications.dart`. Les alarmes sont « inexactes » (pas de permission spéciale) : la notification peut arriver avec quelques minutes d'écart.

## Fonctionnement

Quatre onglets :

- **Aujourd'hui** : progression du jour (anneau), série de jours, examens proches, sujets à revoir. Bouton ✓ ou carte glissée vers la droite = **noter la révision** ; vers la gauche = **demain** (pas le temps). Un bandeau permet d'annuler. Les sujets notés dans la journée passent dans **Revus aujourd'hui**, avec un bouton ↶ pour annuler la révision.
- **Planning** : calendrier du mois (un point par matière, un drapeau les jours d'examen). Toucher un jour liste ce qui est prévu, ou ce qui a été revu ce jour-là. Les rappels après le prochain sont « estimés » (si chaque révision est faite à temps).
- **Matières** : progression de chaque matière, compte à rebours de l'examen, recherche dans tous les sujets. Une matière se filtre par « à revoir / en cours / terminés ».
- **Chapitres** : dans une matière, les sujets se rangent par chapitre (créer, renommer, monter/descendre, supprimer depuis le menu ⋮ de chaque chapitre). Ce qui n'est dans aucun chapitre va dans **Autre**. Chaque chapitre affiche ses sujets, ceux à revoir et sa maîtrise, et se replie d'un toucher. Le chapitre se choisit à l'ajout d'un sujet, ou ensuite via la fiche du sujet (⋮ → Changer de chapitre). Supprimer un chapitre garde ses sujets, qui passent dans « Autre ». Les chapitres sont rangés dans la matière (`chapters`), chaque sujet porte un `chapterId` ; un chapitre supprimé sur un autre appareil renvoie ses sujets dans « Autre ».
- **Progrès** : série actuelle et record, révisions totales, sujets solides, carte d'activité sur 17 semaines, ressenti des révisions (répartition des notes et taux de réussite sur 30 jours), maîtrise par matière.

Planification adaptative (inspirée de SM-2, l'algorithme d'Anki ; code dans `lib/logic/scheduler.dart`) :

- **Premier rappel** le lendemain de l'étude.
- **À chaque révision**, une note. Chaque bouton affiche d'avance la date qu'il donnera.

  | Note | Après l'étude ou un oubli | Ensuite | Facilité du sujet |
  |---|---|---|---|
  | Oublié | demain | demain | −0,2 |
  | Difficile | 3 j | intervalle × 1,2 | −0,15 |
  | Bien | 6 j | intervalle × facilité | inchangée |
  | Facile | 10 j | intervalle × facilité × 1,3 | +0,15 |

  La facilité part de 2,5 (bornée entre 1,3 et 3,2) : un sujet souvent difficile revient plus souvent. Intervalle maximal : 180 jours. Une réussite après un retard compte le temps réellement tenu.
- **Rythme général** (réglages) : Soutenu (×0,7), Normal, Détendu (×1,4) sur tous les intervalles.
- **Solidité du souvenir** (jauge à 5 barres) d'après l'intervalle : fragile (1 j), en cours (3 j), correct (7 j), solide (3 sem.), ancré (2 mois). La maîtrise d'une matière est la moyenne de ses sujets.
- **Date d'examen** : aucun rappel après la veille ; un rappel qui tomberait plus tard est ramené à la veille. Plus aucun rappel une fois l'examen passé.
- **Planning** : les rappels après le prochain sont estimés en supposant des révisions notées « Bien ».
- **Fiche d'un sujet** : les 4 notes directement, la frise du parcours (révisions faites avec leur note, prochaines estimées), « Réétudié aujourd'hui » (relance le cycle en gardant la facilité apprise), « Arrêter / Reprendre les rappels ».
- **Annuler la dernière révision** (fiche d'un sujet, ou « Revus aujourd'hui ») : le sujet retrouve son intervalle, sa facilité et son rappel d'avant, et la révision sort des statistiques. Possible plusieurs fois de suite, à n'importe quel moment, mais pas au-delà d'un « Réétudié aujourd'hui ». Un bandeau « Rétablir » défait l'annulation. Chaque révision enregistre l'état d'avant (`p` dans le JSON) ; pour les révisions plus anciennes, il est estimé (intervalle = écart avec la révision précédente, rappel = jour de la révision).
- **Pas le temps** : « Demain » repousse le rappel sans toucher à l'intervalle.
- **Ajout d'un ancien chapitre** : choisis la vraie date d'étude ; s'il est déjà « en retard », il apparaît tout de suite dans « Aujourd'hui ».
- **Notifications** : une par jour, à l'heure choisie, qui liste les sujets du jour (les retards sont rappelés au prochain créneau). Reprogrammées à chaque modification, au retour dans l'app et à minuit. Un bouton dans les réglages envoie une notification de test.
- **Thème** : automatique, clair ou sombre.
- **Stockage** : local, JSON dans `shared_preferences` (aucun compte, aucun serveur). **Sauvegarde** : copie du JSON dans le presse-papiers, restauration en le collant (les données remplacées sont gardées sous la clé `retiens_topics_v1_before_import`). Les données des versions précédentes (rappels fixes J+1/J+7/J+30) sont reprises : l'intervalle est déduit des dates prévues, l'ancien rythme devient le rythme général équivalent.

## Design

- Police **Manrope** embarquée (`assets/fonts/`, licence OFL).
- Couleurs dans `lib/theme.dart` : bleu `#2A78D6` en couleur principale. Les 8 couleurs de matières forment une palette validée pour le daltonisme et le contraste, avec une variante pour le thème sombre ; la carte d'activité utilise une rampe d'un seul bleu.
- Icône : marque-page avec coche, adaptative (Android 8+, avec version monochrome pour les icônes thématiques d'Android 13+) et PNG pour Android 7 (`android/app/src/main/res/`). Icône de notification dédiée (`drawable/ic_notification.xml`).

## Compte et synchronisation (Firebase)

L'utilisateur peut créer un compte (e-mail + mot de passe) dans Réglages → **Compte**. Ses données sont alors sauvegardées et synchronisées automatiquement entre ses appareils. Sans compte, ou sans configuration Firebase, l'app fonctionne en local comme avant.

### Mise en route (une seule fois)

1. [Console Firebase](https://console.firebase.google.com) : créer un projet (ou en réutiliser un).
2. **Ajouter une application Android** avec le nom de package `com.solobyte.revise`. Télécharger `google-services.json` et le placer dans `android/app/`. Le plug-in Google Services ne s'applique que si ce fichier existe ([android/app/build.gradle.kts](android/app/build.gradle.kts)).
3. **Authentication** → Sign-in method → activer **E-mail/Mot de passe**.
4. **Firestore Database** → Créer une base (région `eur3` ou `europe-west1`), puis **Règles** : coller le contenu de [firestore.rules](firestore.rules). Chacun n'accède qu'à ses propres données.
5. Recompiler et installer l'APK.

### Fonctionnement

- Un document Firestore par compte, `users/{uid}`, qui contient matières, sujets, suppressions, compteurs de révisions par appareil et rythme ([lib/data/sync_merge.dart](lib/data/sync_merge.dart)).
- **Fusion élément par élément** : chaque matière et chaque sujet porte sa date de modification, la plus récente l'emporte. Les suppressions sont propagées (gardées 180 jours). Les révisions du jour sont comptées par appareil, donc deux téléphones s'additionnent au lieu de s'écraser.
- **À la connexion**, les données du téléphone et celles du compte sont fusionnées : rien n'est perdu. Aucun envoi n'a lieu avant la première réponse du serveur, pour qu'un nouveau téléphone vide n'écrase jamais le compte.
- **Ensuite**, chaque modification part après 1,2 s, regroupée avec les suivantes. Les changements faits ailleurs arrivent en direct. Hors connexion, Firestore garde les envois en attente.
- **Réglages propres à l'appareil**, non synchronisés : rappels, thème, sons, vibrations.
- **Déconnexion** : les données restent sur le téléphone. **Supprimer le compte** (mot de passe redemandé) efface le document puis le compte. **Tout effacer**, quand on est connecté, efface aussi le compte et donc les autres appareils.
- **Limite** : si deux appareils modifient le *même* sujet hors connexion, la version modifiée en dernier l'emporte.

## Widgets de l'écran d'accueil (Android)

Deux widgets, à ajouter par un appui long sur l'écran d'accueil → Widgets → Retiens, ou depuis Réglages → **Widgets** :

- **Révisions du jour** (redimensionnable, 3 × 2 par défaut) : date, nombre de sujets à revoir, série, et jusqu'à 4 sujets avec la couleur de leur matière (le nombre de lignes suit la hauteur du widget). Quand tout est revu, il passe au vert (« Journée bouclée ! ») et annonce le prochain rappel. Toucher un sujet ouvre sa fiche, **+** ouvre l'ajout d'un sujet, le reste ouvre l'onglet Aujourd'hui.
- **Série** (2 × 2) : flamme, jours de suite, progression du jour (« 2/4 aujourd'hui »). Orange tant que la série est vivante, gris sinon.

Fonctionnement : l'app prépare les données des **14 prochains jours** à chaque modification ([lib/services/home_widgets.dart](lib/services/home_widgets.dart), paquet `home_widget`). Les widgets natifs (`TodayWidgetProvider.kt`, `StreakWidgetProvider.kt`, mises en page dans `res/layout/widget_*.xml`) se redessinent toutes les 30 minutes en prenant l'entrée du jour. Au changement de date, ils restent donc justes même si l'app n'est pas ouverte : un sujet non revu reste compté les jours suivants, et la série s'éteint si la veille est passée sans révision.

## Sons, vibrations et animations

Chaque événement a son son et son rythme de vibrations (`lib/services/fx.dart`) :

| Événement | Son | Animation |
|---|---|---|
| Oublié | deux notes graves qui descendent | éclat rouge + « demain » |
| Difficile | une note médium | éclat jaune + délai |
| Bien | tierce montante, marimba + cloche | éclat vert + délai |
| Facile | arpège pétillant | éclat bleu, plus d'étincelles |
| Journée terminée | fanfare (arpège, accord, scintillements) | confettis, bannière, carte du jour qui passe au vert avec un trophée |
| Souvenir devenu solide / ancré | montée + deux cloches | bannière |
| Série prolongée (1re révision du jour) | trois notes + souffle | bannière flamme |
| Demain | deux « boop » qui descendent | éclat « Demain », carte qui part à gauche |
| Annuler / Rétablir | glissando descendant | carte qui revient dans la liste |
| Ajout (sujet, matière) | « pop » | éclat « Ajouté » |
| Suppression | choc sourd | — |
| Balayage assez long | petit « tic » | fond qui s'allume, icône qui grossit |
| Choix, filtres, interrupteurs | clic léger | — |

Autres animations :
- cartes qui s'enfoncent à l'appui ;
- listes en cascade, sorties animées (une carte notée s'envole à droite, une carte balayée referme son espace) ;
- fondu entre onglets ;
- compteurs et barres qui se remplissent (Progrès rejoue tout à chaque visite) ;
- flamme de la série qui ondule ;
- calendrier qui glisse d'un mois à l'autre, aussi au doigt ;
- champ vide qui tremble ;
- page précédente visible pendant le geste retour (Android 14+).

Petits bonus : toucher le trophée relance la fête, toucher la flamme la fait crépiter.

- Réglages → **Sons et vibrations** : interrupteurs séparés, et « Écouter les sons » pour essayer chacun.
- Les sons se mêlent à la musique en cours (pas de prise du focus audio) et suivent le volume multimédia.
- Si le téléphone demande de réduire les animations, elles sont coupées.
- Les sons sont **synthétisés** par `tool/synth_sounds.py` (aucun échantillon externe). Pour les retoucher :
  ```bash
  python3 tool/synth_sounds.py /tmp/sons
  for f in /tmp/sons/*.wav; do ffmpeg -y -i "$f" -c:a libvorbis -q:a 5 "assets/sounds/$(basename "$f" .wav).ogg"; done
  ```

## Structure

```
lib/
  main.dart                      point d'entrée, thèmes, rafraîchissement (retour, minuit)
  theme.dart                     thème, couleurs d'état, couleurs des matières
  app_scope.dart                 accès à l'état via InheritedNotifier
  data/app_state.dart            état, statistiques, planning, sauvegarde, notifications
  logic/scheduler.dart           notes, intervalles, examen, projection (pur Dart)
  logic/dates.dart, format.dart  dates et libellés en français
  models/subject.dart, topic.dart
  services/notifications.dart    notifications locales
  services/fx.dart               sons et vibrations
  services/cloud_sync.dart       compte Firebase et synchronisation
  services/home_widgets.dart     données et ouverture des widgets d'écran d'accueil
  data/sync_merge.dart           fusion des données entre appareils (pur Dart)
  widgets/motion.dart            appui, cascade, compteurs, secousse, fondu entre onglets
  widgets/celebrations.dart      confettis, éclats, bannières
  widgets/animated_topics.dart   listes de cartes aux entrées/sorties animées
  widgets/                       carte de sujet, notation, carte d'activité, calendrier
  screens/                       onglets, fiche sujet, matière, éditeur, réglages, recherche
assets/sounds/                   effets sonores (OGG, 164 Ko)
tool/synth_sounds.py             synthétiseur des effets sonores
firestore.rules                  règles de sécurité Firestore
test/
  scheduler_test.dart            intervalles par note, examen, projection, anciennes données
  app_state_test.dart            révision notée, annulation, séries, planning, sauvegarde, migration
  screens_test.dart              parcours de tous les écrans (taille téléphone)
  sync_test.dart                 fusion entre appareils, suppressions, compteurs par appareil
  home_widgets_test.dart         données des widgets (jours à venir, série)
android/app/src/main/kotlin/…   widgets natifs (TodayWidgetProvider, StreakWidgetProvider, WidgetData)
```
