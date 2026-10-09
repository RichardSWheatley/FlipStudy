#if DEBUG
import CoreData
import Foundation
import SwiftData
import os

/// Creates FlipStudy's record types in CloudKit's *development* environment,
/// so they can then be deployed to production in the CloudKit Console.
///
/// Without this, record types only appear once a signed-in device has synced
/// a deck, a card and a study day. Launch a debug build on a device signed in
/// to iCloud with `-initCloudKitSchema` to do it in one go. It writes
/// placeholder records and removes them, using a scratch store, so the real
/// store and the user's data are never touched. Never compiled into release.
enum CloudSchema {
    private static let log = Logger(subsystem: "com.flipstudy.app", category: "CloudSchema")

    static func initializeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") else { return }
        do {
            try autoreleasepool {
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Deck.self, Card.self, StudyDay.self]) else {
                    log.error("Couldn't build a Core Data model from the SwiftData models")
                    return
                }
                let url = FileManager.default.temporaryDirectory.appending(path: "cloud-schema.store")
                let description = NSPersistentStoreDescription(url: url)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Persistence.cloudContainerID)
                description.shouldAddStoreAsynchronously = false

                let container = NSPersistentCloudKitContainer(name: "CloudSchema", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }

                try container.initializeCloudKitSchema()
                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            log.notice("CloudKit development schema initialized")
        } catch {
            log.error("CloudKit schema initialization failed: \(error)")
        }
    }
}
#endif
