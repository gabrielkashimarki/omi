import AppKit

private enum TaskSelectionSnapshotError: Error {
  case searchResultsNotReady
}

@MainActor
extension TasksViewModel {
  func invalidateSelectionOperation() {
    selectionOperationGeneration &+= 1
    isSelectingAllTasks = false
    activeSelectionAllOperationToken = nil
    bulkDeleteInFlight = false
    activeBulkDeleteOperationToken = nil
  }

  func clearMultiSelectionForScopeChange() {
    invalidateSelectionOperation()
    guard multiSelection.isActive else { return }
    mutateMultiSelection(fencesOperation: false) { state in
      state.deselectAll()
    }
    authoritativeSelectionTaskIDs.removeAll()
    selectedAllScope = nil
    selectedAllScopeTaskIDs.removeAll()
    bulkTaskErrorMessage = nil
  }

  func mutateMultiSelection(
    fencesOperation: Bool = true,
    _ mutation: (inout TaskMultiSelectionState) -> Void
  ) {
    var next = multiSelection
    mutation(&next)
    if fencesOperation, next != multiSelection {
      selectionOperationGeneration &+= 1
    }
    multiSelection = next
  }

  func reconcileMultiSelection() {
    guard multiSelection.isActive else { return }
    let visibleIDs = visibleTaskIDsForSelection
    mutateMultiSelection(fencesOperation: false) { state in
      state.reconcile(visibleIDs: visibleIDs, availableTaskIDs: allAvailableTaskIDs)
    }
  }

  func toggleMultiSelectMode() {
    invalidateSelectionOperation()
    let wasActive = multiSelection.isActive
    mutateMultiSelection(fencesOperation: false) { state in
      if state.isActive {
        state.exit()
      } else {
        state.enter()
        state.reconcile(visibleIDs: visibleTaskIDsForSelection)
      }
    }
    if wasActive {
      authoritativeSelectionTaskIDs.removeAll()
      selectedAllScope = nil
      selectedAllScopeTaskIDs.removeAll()
      bulkTaskErrorMessage = nil
    }
  }

  func toggleTaskSelection(
    _ task: TaskActionItem,
    modifiers: TaskMultiSelectionModifiers = .command
  ) {
    mutateMultiSelection { state in
      _ = state.click(task.id, modifiers: modifiers, visibleIDs: visibleTaskIDsForSelection)
    }
  }

  private func taskIDsForSelectionScope(_ scope: SelectionScope) async throws -> [String] {
    switch scope {
    case .search(let query):
      // Search already queries the complete local FTS result set and only caps
      // presentation afterward. Select the full result, not its first 100 rows.
      guard
        normalizedSearchQuery == query,
        completedSearchRequestGeneration == searchRequestGeneration,
        !isSearching
      else {
        throw TaskSelectionSnapshotError.searchResultsNotReady
      }
      return allFilteredDisplayTasks.map(\.id)
    case .taskBucket(let completed):
      return try await selectionSnapshotLoader(completed)
    }
  }

  func selectAllTasks() async {
    guard multiSelection.isActive, !isSelectingAllTasks, !bulkDeleteInFlight else { return }
    selectionOperationGeneration &+= 1
    let scope = currentSelectionScope
    let operationGeneration = selectionOperationGeneration
    selectionAllOperationToken &+= 1
    let operationToken = selectionAllOperationToken
    activeSelectionAllOperationToken = operationToken
    isSelectingAllTasks = true
    bulkTaskErrorMessage = nil
    defer {
      if activeSelectionAllOperationToken == operationToken {
        activeSelectionAllOperationToken = nil
        isSelectingAllTasks = false
      }
    }

    do {
      let taskIDs = try await taskIDsForSelectionScope(scope)
      guard
        selectionOperationGeneration == operationGeneration,
        multiSelection.isActive,
        currentSelectionScope == scope
      else { return }

      authoritativeSelectionTaskIDs.formUnion(taskIDs)
      selectedAllScope = scope
      selectedAllScopeTaskIDs = Set(taskIDs)
      mutateMultiSelection { state in
        state.selectAll(visibleIDs: taskIDs)
      }
    } catch {
      guard
        selectionOperationGeneration == operationGeneration,
        multiSelection.isActive,
        currentSelectionScope == scope
      else { return }
      bulkTaskErrorMessage =
        "Não foi possível acessar a lista completa de tarefas. Nenhuma tarefa adicional foi selecionada. Tente de novo."
      logError("TasksViewModel: Failed to select complete task scope", error: error)
    }
  }

  func toggleSelectAllTasks() async {
    if allTasksInSelectionScopeSelected {
      mutateMultiSelection { state in
        state.deselectAll()
      }
      authoritativeSelectionTaskIDs.removeAll()
      selectedAllScope = nil
      selectedAllScopeTaskIDs.removeAll()
      return
    }
    await selectAllTasks()
  }

  var allTasksInSelectionScopeSelected: Bool {
    guard selectedAllScope == currentSelectionScope, !selectedAllScopeTaskIDs.isEmpty else {
      return false
    }
    return selectedAllScopeTaskIDs.allSatisfy { multiSelection.selectedIDs.contains($0) }
  }

  func deleteSelectedTasks() async {
    guard !bulkDeleteInFlight, !isSelectingAllTasks else { return }
    let orderedIDs = multiSelection.selectedIDs(in: visibleTaskIDsForSelection)
    guard !orderedIDs.isEmpty else { return }
    guard bulkDeleteConfirmation(orderedIDs.count) else { return }
    selectionOperationGeneration &+= 1
    let operationGeneration = selectionOperationGeneration
    let scope = currentSelectionScope
    let ownerGeneration = selectionOwnerGeneration
    bulkDeleteOperationToken &+= 1
    let operationToken = bulkDeleteOperationToken
    activeBulkDeleteOperationToken = operationToken
    bulkDeleteInFlight = true
    defer {
      if activeBulkDeleteOperationToken == operationToken {
        activeBulkDeleteOperationToken = nil
        bulkDeleteInFlight = false
      }
    }

    for id in orderedIDs {
      removeFromDisplay(id)
    }
    let outcome = await bulkDeleteOperation(orderedIDs)
    guard
      selectionOperationGeneration == operationGeneration,
      multiSelection.isActive,
      currentSelectionScope == scope,
      selectionOwnerGeneration == ownerGeneration
    else {
      if currentSelectionScope == scope, selectionOwnerGeneration == ownerGeneration {
        recomputeDisplayCaches()
      }
      return
    }
    switch outcome {
    case .localFailure(let remoteDeletedIDs):
      if !remoteDeletedIDs.isEmpty {
        for id in remoteDeletedIDs {
          chatCoordinator?.purgeState(for: id)
        }
        mutateMultiSelection { state in
          state.removeSelectedIDs(remoteDeletedIDs)
        }
        authoritativeSelectionTaskIDs.subtract(remoteDeletedIDs)
        selectedAllScopeTaskIDs.subtract(remoteDeletedIDs)
      }
      recomputeDisplayCaches()
      if remoteDeletedIDs.isEmpty {
        bulkTaskErrorMessage =
          "Não foi possível apagar as tarefas deste Mac. Nada foi apagado da sua conta. Tente de novo."
      } else {
        bulkTaskErrorMessage =
          "As tarefas foram apagadas da sua conta, mas este Mac não conseguiu terminar de atualizar o cache local. "
          + "Atualize as Tarefas para sincronizar."
      }
      return
    case .remoteFailure(let confirmedIDs):
      for id in confirmedIDs {
        chatCoordinator?.purgeState(for: id)
      }
      if !confirmedIDs.isEmpty {
        mutateMultiSelection { state in
          state.removeSelectedIDs(confirmedIDs)
        }
        authoritativeSelectionTaskIDs.subtract(confirmedIDs)
        selectedAllScopeTaskIDs.subtract(confirmedIDs)
        if selectedAllScopeTaskIDs.isEmpty {
          selectedAllScope = nil
        }
      }
      recomputeDisplayCaches()
      if confirmedIDs.isEmpty {
        bulkTaskErrorMessage =
          "Não foi possível apagar as tarefas selecionadas da sua conta. Nada foi removido deste Mac. "
          + "Tarefas bloqueadas exigem um plano pago. Caso contrário, verifique sua conexão e tente de novo."
      } else {
        bulkTaskErrorMessage =
          "Algumas tarefas foram apagadas, mas as demais tarefas selecionadas não puderam ser apagadas da sua conta. "
          + "Elas continuam selecionadas para você tentar de novo."
      }
      return
    case .ownerChanged:
      recomputeDisplayCaches()
      return
    case .deletedEverywhere:
      for id in orderedIDs {
        chatCoordinator?.purgeState(for: id)
      }
    }

    mutateMultiSelection { state in
      state.removeSelectedIDs(Set(orderedIDs))
      if state.selectionCount == 0 {
        state.exit()
      }
    }
    let deletedIDs = Set(orderedIDs)
    authoritativeSelectionTaskIDs.subtract(deletedIDs)
    selectedAllScopeTaskIDs.subtract(deletedIDs)
    if selectedAllScopeTaskIDs.isEmpty {
      selectedAllScope = nil
    }
  }
}
