package com.brunodobric.gymapp.ui.exercises

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.TabScaffold
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.ExerciseSearch
import com.brunodobric.gymapp.catalog.ExerciseSearchLabels
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.featured
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.history.SessionDetailScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import java.util.UUID

/** Uređivač otvoren s popisa: nova vježba ili postojeća vlastita vježba. */
private const val NEW_EXERCISE = "new"

/**
 * Popis vježbi kataloga i vlastitih vježbi s pretragom, brzim odabirom vrste i listom s filterima
 * (izvor, kategorija, oprema, mišić). Dodir otvara detalj vježbe s poviješću, a vlastita vježba se iz
 * detalja uređuje. Bez upita i otvorenog popisa stoji početna kataloga s karticama vrsta ([ExerciseKindHome]).
 */
@Composable
fun ExercisesScreen(services: AppServices) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val language = catalogLanguage()
    val catalog = remember(language) { services.catalog.summaries(language) }
    var filter by rememberSaveable(stateSaver = ExerciseFilterSaver) { mutableStateOf(ExerciseFilter()) }
    var showsFilters by rememberSaveable { mutableStateOf(false) }
    // Popis otvoren s početne kataloga (kartica vrste, Sve vježbe, Moje vježbe). Pretraga ga otvara sama.
    var listOpen by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    // Nazivi kategorija, mišića i opreme za pretragu: "triceps" pronalazi sve vježbe za triceps.
    val labels = remember(language) {
        ExerciseSearchLabels(
            category = { context.getString(categoryTitle(it)) },
            muscle = { context.getString(muscleTitle(it)) },
            equipment = { context.getString(equipmentTitle(it)) },
        )
    }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    // Otvoreni detalj: "c:<id kataloga>" ili "u:<uuid vlastite vježbe>", te trening otvoren iz povijesti vježbe.
    var detail by rememberSaveable { mutableStateOf<String?>(null) }
    var openedSession by rememberSaveable { mutableStateOf<String?>(null) }

    editing?.let { target ->
        CustomExerciseEditorScreen(
            services = services,
            exerciseId = if (target == NEW_EXERCISE) null else UUID.fromString(target),
            onClose = { editing = null },
        )
        return
    }
    openedSession?.let { id ->
        SessionDetailScreen(services, UUID.fromString(id), onClose = { openedSession = null })
        return
    }
    detail?.let { key ->
        val source = if (key.startsWith("u:")) {
            ExerciseSummary.Source.Custom(UUID.fromString(key.drop(2)))
        } else {
            ExerciseSummary.Source.Catalog(key.drop(2))
        }
        ExerciseDetailScreen(
            services = services,
            source = source,
            onClose = { detail = null },
            onEdit = { editing = it.toString() },
            onOpenSession = { openedSession = it.toString() },
        )
        return
    }

    val summaries = remember(revision, catalog) { store.customExercises.map { it.summary } + catalog }
    val results = remember(filter, summaries, labels) { ExerciseSearch.apply(filter, summaries, labels) }

    val showsHome = !listOpen && filter.query.isEmpty()
    BackHandler(enabled = !showsHome) {
        listOpen = false
        filter = ExerciseFilter()
    }
    val counts = remember(summaries) { ExerciseSearch.countsByKind(summaries) }
    val customCount = remember(revision) { store.customExercises.count { !it.isArchived } }
    val posters = remember {
        val byKind = ExerciseKind.entries.associateWith { kind ->
            services.catalog.featured(kind) { MoveKitAssets.hasPoster(context, it) }.mapNotNull { it.poster }
        }
        byKind::getValue
    }

    if (showsFilters) {
        ExerciseFilterSheet(filter = filter, onChange = { filter = it }, onDismiss = { showsFilters = false })
    }

    TabScaffold(
        title = stringResource(R.string.tab_exercises),
        // Popis otvoren s početne kataloga ima gumb natrag, kao ekran gurnut u NavigationStack na iOS-u.
        navigationIcon = {
            if (!showsHome) {
                IconButton(onClick = {
                    listOpen = false
                    filter = ExerciseFilter()
                }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                }
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { editing = NEW_EXERCISE },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text(stringResource(R.string.custom_exercise_new)) },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            OutlinedTextField(
                value = filter.query,
                onValueChange = { filter = filter.copy(query = it) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text(stringResource(R.string.search_exercises)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            )
            if (showsHome) {
                ExerciseKindHome(counts, customCount, posters, onOpen = { route ->
                    filter = when (route) {
                        is ExerciseListRoute.Kind -> ExerciseFilter(kinds = setOf(route.kind))
                        ExerciseListRoute.All -> ExerciseFilter()
                        ExerciseListRoute.Custom -> ExerciseFilter(origin = ExerciseFilter.Origin.CUSTOM)
                    }
                    listOpen = true
                })
                return@Column
            }
            // Vrsta (Sve, Zagrijavanje, Snaga, Istezanje, Kardio) i gumb za list s filterima.
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val count = filter.activeCount()
                FilterChip(
                    selected = count > 0,
                    onClick = { showsFilters = true },
                    label = {
                        Text(if (count > 0) stringResource(R.string.filters_count, count) else stringResource(R.string.filters))
                    },
                )
                FilterChip(
                    selected = filter.kinds.isEmpty(),
                    onClick = { filter = filter.copy(kinds = emptySet()) },
                    label = { Text(stringResource(R.string.filter_all)) },
                )
                ExerciseKind.entries.forEach { kind ->
                    FilterChip(
                        selected = filter.kinds == setOf(kind),
                        onClick = { filter = filter.copy(kinds = setOf(kind)) },
                        label = { Text(stringResource(kindTitle(kind))) },
                    )
                }
            }
            if (results.isEmpty()) {
                ListItem(headlineContent = { Text(stringResource(R.string.no_results)) })
            }
            LazyColumn {
                items(results, key = { it.id }) { item ->
                    val key = when (val source = item.source) {
                        is ExerciseSummary.Source.Catalog -> "c:" + source.id
                        is ExerciseSummary.Source.Custom -> "u:" + source.id
                    }
                    val details = listOfNotNull(
                        item.category?.let { stringResource(categoryTitle(it)) },
                        item.equipment?.let { stringResource(equipmentTitle(it)) },
                    ).joinToString(" · ")
                    ListItem(
                        headlineContent = { Text(item.name) },
                        supportingContent = if (details.isNotEmpty()) {
                            { Text(details) }
                        } else {
                            null
                        },
                        modifier = Modifier.clickable { detail = key },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
