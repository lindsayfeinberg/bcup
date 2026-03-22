//
//  CommunitiesNavigator.swift
//  bitchcup
//
//  Created by Lindsay Feinberg on 3/22/26.
//
import SwiftUI

@MainActor
final class CommunitiesNavigator: ObservableObject {
    @Published var path = NavigationPath()

    func navigateToDetail(communityId: String) {
        AppDebugLog.log("CommunitiesNavigator: navigateToDetail=\(communityId)")
        var newPath = NavigationPath()
        newPath.append(CommunityRoute.detail(communityId: communityId))
        path = newPath
    }
}
